if (! Meteor.isServer)
  return;

// Lists -- {name: String}
Lists = new Meteor.Collection("lists");

// Publish complete set of lists to all clients.
Meteor.publish('lists', function () {
  return Lists.find();
});


// Todos -- {text: String,
//           done: Boolean,
//           tags: [String, ...],
//           list_id: String,
//           timestamp: Number}
Todos = new Meteor.Collection("todos");

// OFFLINE
// // Publish all items for requested list_id.
// Meteor.publish('todos', function (list_id) {
//   return Todos.find({list_id: list_id});
// });

// Publish all items, which allows the user to switch between lists
// while offline.
Meteor.publish('todos', function () {
  return Todos.find();
});
