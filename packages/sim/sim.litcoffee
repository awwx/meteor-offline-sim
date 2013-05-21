# Simulator #

The simulator runs in the outer window at the URL "/sim".  The
application is run in iframes (each simulated "browser tab" runs in an
iframe).

Within the iframes the application is running a normal Meteor
environment.  Each has its own copy of `Meteor`, each is making its
own livedata connection to the server, etc., just like a regular
Meteor application does when running in multiple real browser tabs.

The applications running inside the simulator get a global variable
called `Sim`, which is a singleton and is shared across the iframes
(it is the same JavaScript object in all the iframes).

`Sim.broadcast` and `Sim.database` emulate cross browser tab messaging
and a browser database.  Because they're actually the same object in
the different iframes, doing something like "broadcasting a message to
all browser tabs" can be done simply by calling the broadcast listener
callbacks.


## Client, Sim and App ##

    return unless Meteor.isClient

    Template.route.sim = -> Session.get('sim')
    Template.route.app = -> Session.get('app')


## Client Sim ##

The outer window runs the simulation.

    if window.location.pathname is '/sim'

      {catcherr} = awwx.err

      window.name = 'sim'
      Session.set('sim', true)
      @isSim = true
      @isApp = false

`Sim` is a singleton shared with the browser tabs.

      @Sim = Sim = {}


`Result` uses `instanceof` which means that to share results across
the simulator and tabs they need to use the same constructor...
Arguably Result should use a duck typing test instead of instanceof.

      Sim.Result = awwx.Result


In the browser, the global `window` object is statically scoped.  If
code in an application iframe calls a function defined in the outer
simulation window and that function references `window`, it will get
the simulation window not the app window.  Thus we need some way for
simulation functions to have access to a per-app object.

Using dynamic scoping would be an easy way to avoid having to pass the
app object around.

This is not currently used, I still need to figure it out.

      AppVar = new Meteor.EnvironmentVariable()

      Sim.getApp = ->
        app = AppVar.get()
        unless app?
          throw new Error("oops, no app env")
        return app

      Sim.withApp = (app, fn) ->
        AppVar.withValue(app, fn)


Are child windows supposed to be online or offline?  (Note that the
simulator is always online).

      Session.set('online', false)
      Sim.online = false


Returns a list of `window` objects of the child windows.

      childWindows = ->
        iframe.contentWindow for iframe in (
          document.getElementsByTagName('iframe'))

      childWindowOfName = (name) ->
        for childWindow in childWindows()
          if childWindow.thisApp?.id is name
            return childWindow
        return null

`Tabs` is a collection with `name` ("tab1", "tab2"...).  I'd
use an array, but when using an array Meteor doesn't know how to avoid
rerendering everything when the array changes.

This doesn't work very well anyway.  Changing a document in the Tabs
collection causes the template to rerender, which loses the "active"
class added by Bootstrap.

      Tabs = new Meteor.Collection(null)

      tabN = 0

      addTab = ->
        ++tabN
        Tabs.insert {name: 'tab' + tabN}
        Meteor.flush()
        $('ul.nav-tabs a:last').tab('show')
        return

      # Meteor.setInterval(
      #   (-> catcherr ->
      #     for tab in Tabs.find().fetch()
      #       Tabs.update(
      #         tab._id,
      #         {$set: {url: childWindowOfName(tab.name)?.location.toString()}}
      #       )
      #   ),
      #   1000
      # )

      tabNames = ->
        names = []
        $('ul.nav-tabs li a').each (i, element) ->
          names.push $(element).attr('href').substr(1)
        return names

      tabIndex = (tabName) ->
        i = tabNames().indexOf(tabName)
        if i is -1 then throw new Error('oops tab name not found in tabs')
        return i

TODO dispose broadcast listeners
TODO abort transaction?

      Sim.closedTabs = {}

      closeTab = (tabName) ->
        # Remember our tab position.
        index = tabIndex(tabName)

        Sim.closedTabs[tabName] = true
        childWindowOfName(tabName)?.thisApp.closed = true
        Tabs.remove Tabs.findOne({name: tabName})._id
        Meteor.flush()

        # Show the tab that was in our position, unless we were
        # the last tab, in which case show the last tab.
        tabs = $('ul.nav-tabs a')
        $(tabs[Math.min(index, tabs.length - 1)]).tab('show')
        return

      Template.connection.connected = ->
        Session.get('online')

Peek at the collections on the server.

      Meteor.subscribe('lists')
      Meteor.subscribe('todos')
      Lists = new Meteor.Collection('lists')
      Todos = new Meteor.Collection('todos')

      Meteor.subscribe("directory");
      Meteor.subscribe("parties");
      Parties = new Meteor.Collection("parties");

      Template.server.server = ->
        'lists: ' + JSON.stringify(Lists.find().fetch(), null, 2) + "\n\n" +
        'todos: ' + JSON.stringify(Todos.find().fetch(), null, 2) + "\n\n" +
        'parties: ' + JSON.stringify(Parties.find().fetch(), null, 2)

      Template.database.database = -> Sim.dumpDatabase()

      Template.sim.events
        'click #goOnline': ->
          Sim.online = true
          Session.set('online', true)
          for child in childWindows()
            child.Meteor.reconnect()

        'click #goOffline': ->
          Sim.online = false
          Session.set('online', false)
          for child in childWindows()
            child.Meteor.default_connection._stream._lostConnection()

        'click #addTab': ->
          addTab()

      Template.tabs.tabs = ->
        Tabs.find({}, {sort: ['name']})

      Template.tabPane.preserve
        'iframe[id]': (node) -> node.id

      Template.tabPane.events
        'click button.closeTab': ->
          closeTab(this.name)


## Client App ##

The windows in the the iframes run the applicaton.

    else # if url isn't "/sim"

      Session.set('app', true)

Keep in mind these variables are *statically scoped*.  If we define a
function in the simulation window and call that function from an app
window, `isSim` will be *true* inside the function.  These variables
do not dynamically tell us where we were called *from*.

      @isSim = false
      @isApp = true

      @Sim = Sim = window.parent.Sim


Redirect to the sim if we're not in an iframe.

      if window.parent is window
        window.location = '/sim'


Munging the retry timeout to a giant value prevents automatic
reconnects, which lets us pretend to be offline.

      Meteor.default_connection._stream._retryTimeout = ->
        365 * 24 * 60 * 60 * 1000


Abort connecting, if we're supposed to be offline.

      unless Sim.online
        Meteor.default_connection._stream._lostConnection()


Things that are per-tab, but internal to the simulation code.
(Regular globals in the app iframe are also per-tab, and they should
be things that would be in a real app).

      @thisApp = {}


Which iframe am I running in?  `id` will be "tab1", "tab2"...

      for iframe in window.parent.document.getElementsByTagName('iframe')
        if iframe.contentWindow is window
          thisApp.id = iframe.name

      unless thisApp.id?
        throw new Error("help! I don't know who I am!")
