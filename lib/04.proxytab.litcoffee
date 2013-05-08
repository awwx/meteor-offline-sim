# Proxy Tab #

A simple system for browser tabs to cooperatively choose one
themselves to be the proxy tab, the tab that is listening to the
subscriptions from the server.

Each tab periodically records a "heartbeat" timestamp in the database.
Tabs that haven't recently updated their heartbeat are considered to
be "inactive".

A tab will become "inactive" if it has been closed.  In addition, iOS
Safari setTimeout events aren't delivered to inactive tabs, and so
they will also become labeled "inactive" using this algorithm.

Currently we don't yet detect tabs that are gone, but we could by
cross-tab messaging and finding out which tabs we're not getting a
reply from.

Each tab periodically checks if it should become the proxy tab.  It
chooses to become the proxy tab if there isn't already a proxy tab, or
if the current proxy tab has become inactive.

Since the check runs in a database transaction, the checks happen one
at a time.  If multiple tabs are eligible to become the proxy tab,
then whichever tab checks first will win.

## Client Sim ##

    if Meteor.isClient and isSim

      Sim.deactivateTab = (tabId) ->
        Sim.broadcast.broadcast 'deactivateTab', [tabId]


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

    now = -> new Date().getTime()

    heartbeat = ->
      database.transaction(thisApp, 'update heartbeat', ->
        database.writeTabHeartbeat thisTabId, now()
      )
      return

    heartbeat()
    heartbeatIntervalId = Meteor.setInterval(heartbeat, 300)


    isTabInactive = (tabId, heartbeats) ->
      heartbeat = heartbeats[tabId]
      return not (heartbeat? and now() - heartbeat < 1000)


TODO clean up heartbeats of dead tabs in the database.

    becameTheProxyTab = ->
      Meteor.defer ->
        currentlyTheProxyTab = true
        nowProxy.call()
        broadcast 'newProxyTab'
        return
      return

    notTheProxyTab = ->
      Meteor.defer ->
        return unless currentlyTheProxyTab
        currentlyTheProxyTab = false
        noLongerProxy.call()
        return
      return

    check = ->
      database.transaction thisApp, 'check proxy tab', ->
        Result.join([
          database.readProxyTab(),
          database.readTabHeartbeats()
        ])
        .then(([proxyTabId, heartbeats]) ->
          if proxyTabId is thisTabId or (proxyTabId? and not isTabInactive(proxyTabId, heartbeats))
            return
          database.writeProxyTab(thisTabId)
          .then(becameTheProxyTab)
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
    checkIntervalId = Meteor.setInterval(check, 1000)


For testing, allow a tab to become "inactive".

    broadcast.listen 'deactivateTab', (tabId) ->
      if tabId is thisTabId
        if heartbeatIntervalId?
          Meteor.clearInterval(heartbeatIntervalId)
          heartbeatIntervalId = null
        if checkIntervalId?
          Meteor.clearInterval(checkIntervalId)
          checkIntervalId = null
      return
