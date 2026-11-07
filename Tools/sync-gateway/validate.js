function (doc, oldDoc, userCtx) {
  if (userCtx.roles.indexOf('_admin') !== -1) return;
  if (userCtx.roles.indexOf('loge_sync_gateway') !== -1) {
    if (doc._deleted || !/^(account|invitation|group|document|shared):[a-f0-9]/.test(doc._id)) {
      throw({forbidden: 'Gateway document scope is invalid.'});
    }
    return;
  }
  function reject() { throw({forbidden: 'Only an encrypted configuration envelope may be stored.'}); }
  if (doc._id !== 'configuration' || doc._deleted || doc.version !== 1 ||
      typeof doc.ciphertext !== 'string' || doc.ciphertext.length < 40 ||
      doc.ciphertext.length > 1000000 || !/^[A-Za-z0-9+/]+={0,2}$/.test(doc.ciphertext) ||
      doc.ciphertext.length % 4 !== 0) reject();
  // CouchDB adds _revisions before validation; the proxy strips replication query options.
  Object.keys(doc).forEach(function (key) {
    if (['_id', '_rev', '_revisions', 'version', 'ciphertext'].indexOf(key) === -1) reject();
  });
}
