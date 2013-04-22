Package.describe({
  summary: "NobleJS's setImmediate polyfill"
});

Package.on_use(function (api) {
  api.add_files('setImmediate.js', ['client', 'server']);
});
