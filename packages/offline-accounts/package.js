Package.describe({
  summary: "make \"Meteor.users\" an offline collection on the client"
});

Package.on_use(function (api) {
  api.use([
    'accounts-base',
    'offline-data'
  ], 'client');
  api.add_files(['munge.js'], 'client');
});
