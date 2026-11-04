#!/usr/bin/env python3
"""Exercise the release publisher without contacting GitHub."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PUBLISHER = Path(__file__).with_name("publish-release.sh")
MOCK_GH = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

path = Path(os.environ["MOCK_RELEASE_STATE"])
state = json.loads(path.read_text())
args = sys.argv[1:]
action = args[1]
state["calls"].append(args)
status = 0
release = state["release"]
if action == "view":
    if release is None:
        status = 1
    else:
        print(json.dumps(release))
elif action == "create":
    if release is not None or state.get("create_failure"):
        status = 1
    else:
        state["release"] = {"isDraft": True, "assets": []}
        if state.pop("create_response_lost", False):
            status = 1
elif action == "upload":
    assert release["isDraft"], "Uploaded to a published release"
    assets = [Path(arg) for arg in args[3:] if arg != "--clobber"]
    partial = state.pop("partial_upload", False)
    if partial:
        assets = assets[:1]
        status = 1
    for asset in assets:
        release["assets"] = [entry for entry in release["assets"] if entry["name"] != asset.name]
        size = 0 if state.get("empty_upload") else asset.stat().st_size
        release["assets"].append({"name": asset.name, "size": size})
elif action == "edit":
    assert release["isDraft"], "Edited a published release"
    if state.get("publish_failure"):
        status = 1
    else:
        release["isDraft"] = False
        if state.pop("publish_response_lost", False):
            status = 1
else:
    raise AssertionError(args)
path.write_text(json.dumps(state))
if status:
    print("simulated GitHub failure", file=sys.stderr)
sys.exit(status)
'''


@unittest.skipUnless(shutil.which("jq"), "jq is required by the release publisher")
class PublishReleaseTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        binary = self.root / "bin"
        binary.mkdir()
        for name, source in (("gh", MOCK_GH), ("sleep", "#!/bin/sh\nexit 0\n")):
            executable = binary / name
            executable.write_text(source)
            executable.chmod(0o755)
        self.state_path = self.root / "release.json"
        self.env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"],
                        MOCK_RELEASE_STATE=str(self.state_path))
        self.notes = self.root / "release notes.md"
        self.notes.write_text("Release notes\n")
        self.assets = [self.root / name for name in ("loge-iOS.ipa", "loge-tvOS.ipa", "loge macOS.dmg")]
        for asset in self.assets:
            asset.write_bytes(b"fixture artifact")

    def run_publisher(self, release=None, **faults):
        self.state_path.write_text(json.dumps(dict(release=release, calls=[], **faults)))
        result = subprocess.run(
            ["bash", str(PUBLISHER), "build-89", "1.0 (89)", "fixture-commit", str(self.notes),
             *(str(asset) for asset in self.assets)], env=self.env, text=True,
            capture_output=True, timeout=10)
        return result, json.loads(self.state_path.read_text())

    def complete_release(self, draft):
        return {"isDraft": draft, "assets": [
            {"name": asset.name, "size": asset.stat().st_size} for asset in self.assets]}

    def assert_complete(self, state):
        self.assertEqual(state["release"], self.complete_release(False))

    def actions(self, state):
        return [call[1] for call in state["calls"]]

    def test_absent_release_is_created_uploaded_and_published(self):
        result, state = self.run_publisher()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_complete(state)
        create = next(call for call in state["calls"] if call[1] == "create")
        self.assertIn("--draft", create)
        self.assertIn("fixture-commit", create)
        edit = next(call for call in state["calls"] if call[1] == "edit")
        self.assertIn("--latest", edit)

    def test_existing_partial_draft_is_resumed(self):
        draft = self.complete_release(True)
        draft["assets"] = draft["assets"][:1]
        result, state = self.run_publisher(draft)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_complete(state)
        self.assertNotIn("create", self.actions(state))

    def test_published_complete_release_is_accepted_without_mutations(self):
        result, state = self.run_publisher(self.complete_release(False))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.actions(state), ["view"])

    def test_published_release_with_missing_assets_is_rejected(self):
        release = self.complete_release(False)
        release["assets"].pop()
        result, state = self.run_publisher(release)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing to change", result.stderr)
        self.assertEqual(self.actions(state), ["view"])

    def test_published_release_with_empty_asset_is_rejected(self):
        release = self.complete_release(False)
        release["assets"][0]["size"] = 0
        result, state = self.run_publisher(release)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.actions(state), ["view"])

    def test_partial_upload_failure_is_retried_while_draft(self):
        result, state = self.run_publisher(partial_upload=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_complete(state)
        self.assertEqual(self.actions(state).count("upload"), 2)
        self.assertEqual(self.actions(state).count("create"), 1)

    def test_lost_creation_response_reconciles_existing_draft(self):
        result, state = self.run_publisher(create_response_lost=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_complete(state)
        self.assertEqual(self.actions(state).count("create"), 1)

    def test_lost_publish_response_reconciles_published_release(self):
        result, state = self.run_publisher(publish_response_lost=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_complete(state)
        self.assertEqual(self.actions(state).count("edit"), 1)

    def test_permanent_creation_failure_has_bounded_retries(self):
        result, state = self.run_publisher(create_failure=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.actions(state).count("create"), 3)
        self.assertNotIn("upload", self.actions(state))
        self.assertIn("after 3 attempts", result.stderr)

    def test_empty_uploaded_assets_are_never_published(self):
        result, state = self.run_publisher(empty_upload=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(state["release"]["isDraft"])
        self.assertEqual(self.actions(state).count("upload"), 3)
        self.assertNotIn("edit", self.actions(state))

    def test_permanent_publish_failure_leaves_a_resumable_draft(self):
        result, state = self.run_publisher(publish_failure=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state["release"], self.complete_release(True))
        self.assertEqual(self.actions(state).count("edit"), 3)

    def test_empty_local_artifact_is_rejected_before_github_requests(self):
        self.assets[0].write_bytes(b"")
        result, state = self.run_publisher()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.actions(state), [])


if __name__ == "__main__":
    unittest.main()
