function (doc, oldDoc, userCtx) {
  if (userCtx.roles.indexOf('_admin') !== -1) return;
  // Only the gateway writes, and only the kinds of document it manages.
  if (userCtx.roles.indexOf('loge_sync_gateway') === -1 || doc._deleted ||
      !/^(account|invitation|group|document|shared):[a-f0-9]/.test(doc._id)) {
    throw({forbidden: 'Only the sync gateway may write, within its document scope.'});
  }
}
