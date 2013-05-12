Package.describe({
  summary: "simulated browser database"
});

Package.on_use(function (api) {
  api.use(['awwx-err', 'awwx-setimmediate', 'coffeescript', 'sim'], 'client');
  api.add_files(['database.litcoffee'], 'client');
});
