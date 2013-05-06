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

Each tab also periodically checks if it should become the proxy tab.
It chooses to become the proxy tab if there isn't already another tab
which is already the proxy tab, or if the current proxy tab has
become inactive.

Since the check runs in a database transaction, the checks happen one
at a time.  If multiple tabs are eligible to become the proxy tab,
then whichever tab checks first will win.


## Client App ##

    return unless Meteor.isClient and isApp

    Fanout = awwx.Fanout
    {Result} = Sim

The real system would use `Random.id()`.

    @thisTabId = thisApp.id


Called when this tab becomes the proxy tab.

    @nowProxy = new Fanout()

    # nowProxy.listen ->
    #   console.log thisApp.id, 'is now the proxy tab'


    now = -> new Date().getTime()

    heartbeat = ->
      database.transaction(thisApp, 'update heartbeat', ->
        database.writeTabHeartbeat thisTabId, now()
      )
      return

    heartbeat()
    setInterval(heartbeat, 300)

    isTabInactive = (tabId, heartbeats) ->
      heartbeat = heartbeats[tabId]
      return not (heartbeat? and now() - heartbeat < 1000)


TODO clean up heartbeats of dead tabs in the database.

    check = ->
      database.transaction thisApp, 'check proxy tab', ->
        Result.join([
          database.readProxyTab(),
          database.readTabHeartbeats()
        ])
        .then(([proxyTabId, heartbeats]) ->
          if proxyTabId? and not isTabInactive(proxyTabId, heartbeats)
            return
          database.writeProxyTab(thisTabId)
          .then(->
            Meteor.defer -> nowProxy.call()
            return
          )
        )
      return

Do a check immediately, so that if we're the first tab we become the
proxy tab right away.  But run the check in the next tick of the
event loop to give the offline code a chance to register its listener.

    Meteor.defer check
    Meteor.setInterval(check, 1000)
