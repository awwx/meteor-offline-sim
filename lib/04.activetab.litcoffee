# Active Tab #

A simple system for one browser tab to promote itself to be the
"active tab", the tab that is listening to the subscriptions from the
server.

Each tab periodically records a "heartbeat" timestamp in the database.
Tabs that haven't recently updated their heartbeat are considered to
be "inactive".

A tab will become "inactive" if it has been closed.  In addition, iOS
Safari setTimeout events aren't delivered to inactive tabs, and so
they will also become labeled "inactive" using this algorithm.

Each tab also periodically checks if it should become the active tab.
It chooses to become the active tab if there isn't already another tab
which is currently the active tab which hasn't become inactive.

Since the check runs in a database transaction, the checks happen one
at a time.  If multiple tabs are eligible to become the active tab,
then whichever tab happens to check first will win.

TODO I don't actually like the name "active tab" because its confusing
with which tab is the active tab in the browser.  Maybe call it the
"master" or "primary" or "leader" or something.


## Client App ##

    return unless Meteor.isClient and isApp

    Fanout = awwx.Fanout
    {Result} = Sim

The real system would use `Random.id()`.

    @thisTabId = thisApp.id


Called when this tab becomes the active tab.

    @nowActive = new Fanout()

    # nowActive.listen ->
    #   console.log thisApp.id, 'is now the active tab'


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
      database.transaction thisApp, 'check active tab', ->
        Result.join([
          database.readActiveTab(),
          database.readTabHeartbeats()
        ])
        .then(([activeTabId, heartbeats]) ->
          if activeTabId? and not isTabInactive(activeTabId, heartbeats)
            return
          database.writeActiveTab(thisTabId)
          .then(->
            Meteor.defer -> nowActive.call()
            return
          )
        )
      return

Do a check immediately, so that if we're the first tab we become the
active tab right away.  But run the check in the next tick of the
event loop to give the offline code a chance to register its listener.

    Meteor.defer check
    Meteor.setInterval(check, 1000)
