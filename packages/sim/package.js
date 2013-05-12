Package.describe({
  summary: "simulate browser tabs"
});

Package.on_use(function (api) {
  api.use(['awwx-fanout', 'awwx-result', 'coffeescript', 'templating'], 'client');
  api.add_files(['route.html', 'sim.css', 'sim.html', 'sim.litcoffee'], 'client');
});
