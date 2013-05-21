if (! isApp)
  return;


Meteor.users = Offline.wrapCollection(Meteor.users);


// This is Meteor.loginWithToken from
// packages/accounts-base/localstorage_token.js with
// "_suppressLoggingIn" added.

Meteor.loginWithToken = function (token, callback) {
  Accounts.callLoginMethod({
    methodArguments: [{resume: token}],
    userCallback: callback,
    _suppressLoggingIn: true
  });
};


// But the original Meteor.loginWithToken has already been
// called in AUTO-LOGIN...

Accounts._setLoggingIn(false);
