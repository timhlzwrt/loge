#!/bin/sh
set -eu
tools_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
curl -L --fail --max-time 45 https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4 -o /tmp/loge-fixture-video.mp4
python3 - <<'PY'
import wave,math,struct
for language,hz in [('en',440),('de',660)]:
    with wave.open('/tmp/loge-tone-'+language+'.wav','wb') as output:
        output.setparams((1,2,48000,0,'NONE','not compressed'))
        block=b''.join(struct.pack('<h',int(4000*math.sin(2*math.pi*hz*i/48000))) for i in range(48000))
        for _ in range(60): output.writeframesraw(block)
PY
swiftc -parse-as-library -module-cache-path /tmp/loge-swift-module-cache "$tools_dir/generate-playback-fixture.swift" -o /tmp/loge-make-multiaudio
/tmp/loge-make-multiaudio
