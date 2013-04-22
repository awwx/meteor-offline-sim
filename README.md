# Offline Algorithm Simulation #

This is a simulation of one approach for storing data offline
in Meteor.

Using a simulator makes it easier to figure out whether the algorithm
is a good idea, without having to first implement all the details of
an actual browser database or cross tab communication.

To run the simulator with the "todos" example:

    $ git clone git://github.com/awwx/meteor-offline-sim.git
    $ cd meteor-offline-sim
    $ meteor

(Note you won't get a todo list automatically selected for you because
the "subscription complete" callback isn't implemented yet; just click
on one of the todo lists yourself).


## Simulator ##

The simulator runs in the parent window and the simulated "browser
tabs" run in iframes.  The "database" (which in a real system would be
an IndexedDB or Web SQL database in the browser) is emulated in memory.

Clicking the "Go Online" or "Go Offline" button causes the
applications in the iframes to connect / disconnect from the Meteor
server.  The simulator has its own Meteor connection (which is always
connected) to display the contents of the collections on the server.

If you close the real browser window and open it again, the contents
of the "database" will be cleared.  (This is like a new user opening
the application for the first time).  Likewise if you open a second
real browser window, you'll get a separate instance of the simulator
-- as if two different people were using the application.  This lets
you see how changes made by one browser propagate to the server and
back to the other browser.


## Offline Algorithm ##

This approach to offline data creates an "offline collection" on top
of standard, unmodified Meteor.  This has some code duplication and
inefficiencies, but is a reasonable place to start to find out what is
a good algorithm.

Offline collections are reactively shared across browser tabs, so
local changes made in one will be visible in another even when
offline.

Because tabs share data, subscriptions are merged across
tabs: if one tab makes a subscription then all tabs will be
subscribed.  (Currently todo is unsubscribing: at the moment once a
subscription is made it lasts forever).

The core of the implementation is essentially a reimplementation of
the code to run method stubs in livedata_connection.js, with
relevant data structures such as "_documentsWrittenByStub" moved into
the database.

I took raix's suggestion of implementing an "offline connection" which
wraps the real livedata connection as a way to get a Meteor.Collection
to run the offline stub code instead of the regular stub code.  So far
this seems to be working.


## Ramifications ##

With this algorithm it's normal for an app to make a method call (such
as to update a document) while offline, and then later (perhaps after
the application window has been closed and then later opened again) to
be able to connect to the server and to deliver the method call.

This means that it no longer works to use function callbacks to report
method completion (and thus collection modification completion): the
function instance will no longer exist when the application is opened
a second time.

Sharing subscriptions across browser tabs means that applications can
no longer rely entirely on server-side filtering; applications will
need to filter collections on the client instead of or in addition to
on the server.  (Applications may want to do less filtering on the
server anyway so that a complete set of data is available for offline
use).

No attempt is made to avoid running method calls more than once on the
server.  This can happen if a tab dies in between sending a method to
the server and getting the "method completed" reply; and when an
application comes online multiple tabs can attempt to deliver queued
methods.  This is probably OK for idempotent method calls, though some
thought would need to be given to delivering methods in order.

For non-idempotent methods calls we could have the server keep a list
of recently seen methods and to avoid running duplicates.  But the
problem there is then we'd need to expire the list of seen method ids
to avoid having the list grow ubound... and if someone enters an
important note in their device and then loses it for a week and then
finally goes online again, do we really want to throw away that update
because it's past the expiration period?


## TODO ##

Subscriptions should be unsubscribed when no tabs are subscribing to a
subscription any more.

Will need a mechanism for detecting when tabs are dead or have been
closed, not just inactive, to know when a tab is no longer subscribing
to a subscription.

The code doesn't yet notice when documents have been deleted on the
server while the application was closed.  (Will need to listen for
subscriptions ready and then delete documents that are no longer in
the server collection).

Offline applications will typically need to do some kind of conflict
resolution on the server.  (For example, suppose the user types in a
short note while offline, and then on another computer types in a long
note into the same field, and then goes online with the first device.
It would be an unpleasant surprise if the long note was deleted and
replaced by the short note).  This may not have a direct impact on the
offline implementation on the client, but it would be nice to have
some accommodation or default implementation on the server.

Currently unimplemented is nested method stubs.

Still todo is using offline collections with other connections besides
the default connection.  (This mostly involves updating the database
code so that the key to documents and such is [connection,
collectionName, docId]).

Completely ignored at the moment is logging in / logging out:
`userId`, `wait` methods, perhaps clearing database data on logout, etc.

Some mechanism to get method completed events.

Figure out if there's some way to support the `autopublish` package.

And a zillion other implementation details.


## Race conditions ##

Database operations in the browser run across multiple ticks of the
event loop: in one tick you start a transaction, you get a callback
when you've acquired the transaction lock and have an active
transaction and fire off a read request, and then in another callback
you get the result of the read and fire off a write request...

Thus while database operations are atomic with respect to each other
(only one transaction will be active at a time), they are not atomic
with respect to other events such as user actions or collection
updates coming from the server or other tabs.  Thus for example
collections can change between the steps of a database transaction.

The danger is without being careful we might get obscure intermittent
and unreproducable bugs: code which will usually run fine but then
occasionally the timing will happen to be just right and then it will
break.

This implementation is just a first sketch at interfacing Meteor
collections with the browser database; some more careful thought and
review will be needed to figure out what race conditions we have or
don't have.


## Simulator Internals ##

Normally code in different browser windows or tabs that were opened
independently by the user don't have direct access to each other's
variables and functions, even if both tabs are open on the same
domain.

This is not a security policy as such (the browser's Same Origin
Policy would be sufficient), but browsers such as Chrome open
different tabs in different processes.  This means that different tabs
are running separate event loops in separate memory spaces.  Even if
one tab was allowed to "poke" data into the memory space of another
tab, to the other tab it would appear that its variables were being
changed at random times.

However when a web page has iframes opened on the same domain, the two
windows *do* have access to each other's data and functions.  This is
possible because there is actually only one runtime shared between the
parent window and the child windows: one event loop, and one memory
space.

The simulator emulates browser tabs by opening each "tab" in an
iframe.  This allows each tab to be running its own copy of Meteor,
but behind the scenes the tabs can communicate through shared data and
functions through the parent window.  This allows "cross browser tab
communication" to be simulated simply by calling the broadcast
listener function in each tab, and the data of the emulated "browser
database" to be held in memory.


### Simulator Gotchas ###

#### Separate constructors ####

Code running in an iframe can share data simply by referencing the
parent window:

    window.parent.foo = [1, 2, 3]

but there are some surprises.  If another iframe checks to see if
`foo` is an array:

    window.parent.foo instanceof Array

the answer is actually `false`!  Each window has its own
[separate Array constructor](https://developer.mozilla.org/en-US/docs/JavaScript/Reference/Operators/instanceof#instanceof_and_multiple_context_%28e.g._frames_or_windows%29),
and `instanceof` checks to see if the object's prototype is `===` to
the constructor.

This may be weird, but JavaScript allows you to add your own methods
to built-in types such as arrays.  If windows shared constructors then
loading a library such as [prototype](http://prototypejs.org/) in one
window would cause the behavior of all windows to change, even those
that didn't load the library themselves.

An easy way to work around this is to only share serialized data:

    window.parent.foo = JSON.stringify([1, 2, 3])


#### Static scoping of `window` ####

The description of iframes having a "different runtime environments"
might give the impression that there might be some kind of dynamic
scoping going on.  That is, suppose in one window we define a
function:

    foo = function () {
      console.log(window.bar);
    };

and we call that function from another window.  Which window does
`window` in the code refer to?  If `window` was dynamically scoped,
connected to the "runtime environment" somehow, then we could imagine
that `window` in `foo` might refer to the window that we're calling
from.

Nope.  `window` is statically scoped, as if code defined in a window
was wrapped in

    (function (window) {
      ...
    )(theWindowInstance);

thus `window` in code always refers to the window the code was defined
*in*, not where it is being called *from*.

This isn't a big deal in practice, it just means that the only code
that implicitly knows what window it is being run from is code defined
in that window.


#### No real concurrency ####

Since the iframes in the simulator share an event loop there's no
actual concurrency going on, as there would be in real browser tabs
running separate processes.  So some race conditions that might be
bugs in a real system might not show up in the simulator.
