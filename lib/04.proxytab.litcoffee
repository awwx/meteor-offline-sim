# Proxy Tab #

A simple system for browser tabs to cooperatively choose one
themselves to be the proxy tab, the tab that is listening to the
subscriptions from the server.

Each tab periodically records a "heartbeat" timestamp in the database.
Tabs that haven't recently updated their heartbeat are considered to
be "inactive".

TODO rename to avoid confusion with which tab is the selected tab in
the browser UI?

A tab will become "inactive" if it has been closed.  In addition, iOS
Safari setTimeout events aren't delivered to inactive tabs, and so
they will also become labeled "inactive" using this algorithm.

Each tab periodically checks if it should become the proxy tab.  It
chooses to become the proxy tab if there isn't already a proxy tab, or
if the current proxy tab has become inactive.

In most browsers it doesn't matter which tab is active (selected in
the tab list and visible to the user); a tab will function just as
well as the proxy tab whether it is selected or not.  In iOS Safari
the tab selected and visible in the UI will become the proxy tab, as
setInterval events are not delivered to the other tabs and they become
labeled "inactive".

Since the check runs in a database transaction, the checks happen one
at a time.  If multiple tabs are eligible to become the proxy tab,
then whichever tab checks first will win.

The proxy tab sends out a "ping" broadcast, to which all the tabs
respond by recoding their "alive" timestamp in the database.  In iOS
Safari inactive tabs still receive storage events, so they can be
detected by this mechanism.  The proxy tab marks tabs as "dead" if
they don't respond to the ping.


## Client Sim ##

    if Meteor.isClient and isSim


Allow tabs to be deactivated in simulation.

      Sim.deactivatedTabs = {}

      Sim.deactivateTab = (tabId) ->
        Sim.deactivatedTabs[tabId] = true

      Sim.activateTab = (tabId) ->
        delete Sim.deactivatedTabs[tabId]


## Client App ##

    return unless Meteor.isClient and isApp

    Fanout = awwx.Fanout
    {Result} = Sim

The real system would use `Random.id()`.

    @thisTabId = thisApp.id


Who is really the proxy tab is kept transactionally in the database;
this keeps track of whether we notified ourselves of a change in proxy
status.

    currentlyTheProxyTab = false

Called when this tab becomes the proxy tab.

TODO maybe this could be a reactive status?  But not sure whether it
is a good idea to get Deps involved in the middle of this or not.

    @nowProxy = new Fanout()

    @noLongerProxy = new Fanout()

    nowProxy.listen ->
      console.log thisApp.id, 'is now the proxy tab'

    noLongerProxy.listen ->
      console.log thisApp.id, 'is no longer the proxy tab'


Notification to the proxy tab of tabs that have died.

    @tabsAreDead = new Fanout()

    tabsAreDead.listen (tabIds) ->
      console.log 'tabs are dead', tabIds


    now = -> new Date().getTime()

    heartbeat = ->
      return if Sim.deactivatedTabs[thisTabId]
      database.transaction(thisApp, 'update heartbeat', ->
        database.writeTabHeartbeat thisTabId, now()
      )
      return

    heartbeat()
    Meteor.setInterval(heartbeat, 300)


    isTabInactive = (tabId, heartbeats) ->
      heartbeat = heartbeats[tabId]
      return not (heartbeat? and now() - heartbeat < 1000)


TODO clean up heartbeats of dead tabs in the database.

    becameTheProxyTab = ->
      currentlyTheProxyTab = true
      nowProxy()
      broadcast 'newProxyTab'
      return

    notTheProxyTab = ->
      Meteor.defer ->
        return unless currentlyTheProxyTab
        currentlyTheProxyTab = false
        noLongerProxy()
        return
      return

In iOS Safari delivery of setTimeout or setInterval events for an
inactive tab is delayed until the tab becomes active again, but as
long as the tab hasn't actually been unloaded it will still receive
other events such as the storage event we use for cross-tab
communication.

    lastPing = null
    tabsAliveAtLastPing = {}

    pingOtherTabs = (alives) ->
      lastPing = now()
      tabsAliveAtLastPing = alives
      Meteor.defer -> broadcast 'ping'
      return

    broadcast.listen 'ping', ->
      database.transaction thisApp, 'record tab alive', ->
        database.writeTabAlive(thisTabId, now())

    someTabsAreDead = (tabIds) ->
      database.mustBeInTransaction()
      Result.join([
        database.removeTabHeartbeats(tabIds)
        database.removeTabAlives(tabIds)
        database.removeSubscriptionsOfTabs(tabIds)
      ]).then(->
        Meteor.defer -> tabsAreDead(tabIds)
        return
      )


New tabs may have opened since the last ping, and we don't want to
mark them as dead just because they haven't gotten a ping yet.

    asTheProxyTab = ->
      database.mustBeInTransaction()
      database.readTabAlives()
      .then((alives) ->
        if lastPing? and now() - lastPing > 300
          deadTabs = []
          for tabId, timestamp of alives
            if tabId of tabsAliveAtLastPing and alives[tabId] < lastPing
              deadTabs.push tabId

          if deadTabs.length > 0
            return someTabsAreDead(deadTabs).then(-> alives)
          else
            return alives
        else
          return alives
      ).then((alives) ->
        throw new Error('die') unless alives?
        return pingOtherTabs(alives)
      )

    check = ->
      return if Sim.deactivatedTabs[thisTabId]
      database.transaction thisApp, 'check proxy tab', ->
        Result.join([
          database.readProxyTab(),
          database.readTabHeartbeats()
        ])
        .then(([proxyTabId, heartbeats]) ->
          if proxyTabId is thisTabId
             return asTheProxyTab()
          if proxyTabId? and not isTabInactive(proxyTabId, heartbeats)
            return
          database.writeProxyTab(thisTabId)
          .then(->
            Meteor.defer ->
              becameTheProxyTab()
              asTheProxyTab()
              return
            return
          )
        )
      return

    broadcast.listen 'newProxyTab', ->
      database.transaction thisApp, 'new proxy tab', ->
        database.readProxyTab()
        .then((proxyTabId) ->
          if proxyTabId isnt thisTabId
            notTheProxyTab()
          return
        )
      return


Do a check immediately, so that if we're the first tab we become the
proxy tab right away.  But run the check in the next tick of the
event loop to give the offline code a chance to register its listener.

    Meteor.defer check
    Meteor.setInterval(check, 1000)
