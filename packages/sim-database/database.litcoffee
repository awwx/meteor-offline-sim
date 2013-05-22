# Database #

The simulated browser database, which in a real system would be
IndexedDB or Web SQL Database.  In the simulator the database data is
simply kept in memory.


## Client Sim ##

    return unless Meteor.isClient

    if isSim

      {Result} = Sim
      {reportError} = awwx.err


This version of bind prints exceptions to the console log.  Not using
this yet.

      bind = (fn, _this) ->
        Meteor.bindEnvironment(
          fn,
          ((exception) ->
            Meteor._debug exception
            Meteor._debug exception.stack if exception?.stack?
          ),
          _this
        )


All databases reads and writes happen within a database transaction.

      defer = (fn) ->
        setImmediate fn

      transactionQueue = []
      inTransaction = false

      runNextOnTransactionQueue = ->
        if inTransaction then throw new Error('oops')
        if transactionQueue.length > 0
          entry = transactionQueue.shift()
          runTransaction(entry)
        return

      runTransaction = ({app, description, fn, result}) ->
        if inTransaction then throw new Error('oops')
        inTransaction = true
        defer ->
          ret = Sim.withApp(app, fn)
          unless ret instanceof Result
            throw new Error("transaction fn did not return a Result: #{ret}")
          ret.into(result)
          result.done().timeout(2000).onFailure ->
            reportError "! transaction: #{description}: timeout"
          result.callback ->
            inTransaction = false
            runNextOnTransactionQueue()
            return
          return
        return

      Sim.transaction = (app, description, fn) ->
        result = new Result()
        transactionQueue.push({app, description, fn, result})
        unless inTransaction
          runNextOnTransactionQueue()
        return result


Our dependency for the database data changing, so that we can
reactively update the database dump tab.

      databaseDep = new Deps.Dependency


Store data as strings to avoid objects and arrays constructed in one
tab not being an instanceof Object or Array in another tab.

      Sim.databaseData = {
        docs:                 '{}'
        updateCount:          '1'
        tabUpdatePointers:    '{}'
        updates:              '[]'
        stubDocuments:        '{}'
        queuedMethods:        '{}'
        tabSubscriptions:     '[]'
        subscriptions:        '{}'
        methodsHoldingUpSubs: '{}'
        proxyTab:             'null'
        tabHeartbeats:        '{}'
        tabAlives:            '{}'
      }

Don't include the tab heartbeats in the dump because they change
constantly.

      Sim.dumpDatabase = ->
        databaseDep.depend()
        data = Sim.databaseData
        return (
          """
          proxyTab: #{data.proxyTab}

          subscriptions: #{data.subscriptions}

          tabSubscriptions: #{data.tabSubscriptions}

          queuedMethods: #{data.queuedMethods}

          methodsHoldingUpSubs: #{data.methodsHoldingUpSubs}

          updateCount: #{data.updateCount}

          tabUpdatePointers: #{data.tabUpdatePointers}

          updates: #{data.updates}

          stubDocuments: #{data.stubDocuments}

          docs: #{data.docs}
          """
        )

      Sim.databaseChanged = ->
        setImmediate -> databaseDep.changed()


## Client App ##

    if isApp

      Result = Sim.Result

      @database = {}

      database.transaction = Sim.transaction


TODO don't know how to implement this.

      database.mustBeInTransaction = ->
        # unless ...
        #   throw new Error("not in a transaction")
        return


Pretty-print so that it's readable in the dump.

      stringify = (x) ->
        JSON.stringify(x, null, 2)


Serialize objects in sorted key order so that they compare equal if
they are structurally equal.

      serialize = awwx.canonicalStringify


Documents are a mirror of the server collection plus local
modifications made by stubs.

      getDocs = ->
        JSON.parse(Sim.databaseData.docs)

      setDocs = (docs) ->
        Sim.databaseData.docs = stringify(docs)
        Sim.databaseChanged()
        return

      database.readDocs = ->
        database.mustBeInTransaction()
        return Result.completed(getDocs())

      database.readDocsInCollection = (collectionName) ->
        database.mustBeInTransaction()
        return Result.completed(getDocs()[collectionName] ? {})

      database.readDoc = (collectionName, docId) ->
        database.mustBeInTransaction()
        return Result.completed(getDocs()[collectionName]?[docId])

      database.writeDoc = (collectionName, doc) ->
        database.mustBeInTransaction()
        docs = getDocs()
        Meteor._ensure(docs, collectionName)[doc._id] = doc
        setDocs docs
        return Result.completed()

      database.deleteDoc = (collectionName, docId) ->
        database.mustBeInTransaction()
        docs = getDocs()
        delete docs[collectionName]?[docId]
        setDocs docs
        return Result.completed()


Documents written by a method stub.  Cleared once the method call
completes.

      getStubDocs = ->
        JSON.parse(Sim.databaseData.stubDocuments)

      setStubDocs = (stubDocs) ->
        Sim.databaseData.stubDocuments = stringify(stubDocs)
        Sim.databaseChanged()
        return

      database.addDocumentWrittenByStub = (methodId, collectionName, docId) ->
        database.mustBeInTransaction()
        stubDocs = getStubDocs()
        Meteor._ensure(stubDocs, collectionName, docId)[methodId] = true
        setStubDocs stubDocs
        return Result.completed()

      database.wasDocumentWrittenByStub = (collectionName, docId) ->
        database.mustBeInTransaction()
        return Result.completed(getStubDocs()[collectionName]?[docId]?)

      database.removeDocumentsWrittenByStub = (methodId) ->
        database.mustBeInTransaction()
        documentsNowFree = []
        stubDocs = getStubDocs()
        for collectionName of stubDocs
          for docId of stubDocs[collectionName]
            if stubDocs[collectionName][docId][methodId]
              delete stubDocs[collectionName][docId][methodId]
              if _.isEmpty(stubDocs[collectionName][docId])
                delete stubDocs[collectionName][docId]
                documentsNowFree.push({collectionName, docId})
         setStubDocs stubDocs
         return Result.completed(documentsNowFree)

      database.readOutstandingMethodsWithStubDocuments = ->
        database.mustBeInTransaction()
        methodIds = {}
        stubDocs = getStubDocs()
        for collectionName, collectionDocs of stubDocs
          for docId, methods of collectionDocs
            for methodId of methods
              methodIds[methodId] = true
        return Result.completed(_.keys(methodIds))


Queued methods are method calls made on the client that haven't been
acknowledged by the server yet.

      getQueuedMethods = ->
        JSON.parse(Sim.databaseData.queuedMethods)

      setQueuedMethods = (queuedMethods) ->
        Sim.databaseData.queuedMethods = stringify(queuedMethods)
        Sim.databaseChanged()
        return

      database.addQueuedMethod = (methodId, name, args) ->
        database.mustBeInTransaction()
        queuedMethods = getQueuedMethods()
        queuedMethods[methodId] = {name, args}
        setQueuedMethods queuedMethods
        return Result.completed()

      database.readQueuedMethods = ->
        database.mustBeInTransaction()
        return Result.completed(getQueuedMethods())

      database.removeQueuedMethod = (methodId) ->
        database.mustBeInTransaction()
        queuedMethods = getQueuedMethods()
        delete queuedMethods[methodId]
        setQueuedMethods queuedMethods
        return Result.completed()


Tab heartbeat are used to detect tabs that are not longer responding.

      getHeartbeats = ->
        JSON.parse(Sim.databaseData.tabHeartbeats)


Deliberately not calling `databaseChanged()` here because we don't
include the heartbeats in the database dump.

      setHeartbeats = (heartbeats) ->
        Sim.databaseData.tabHeartbeats = stringify(heartbeats)
        return

      database.writeTabHeartbeat = (tabId, timestamp) ->
        database.mustBeInTransaction()
        heartbeats = getHeartbeats()
        heartbeats[tabId] = timestamp
        setHeartbeats heartbeats
        return Result.completed()

      database.readTabHeartbeats = ->
        database.mustBeInTransaction()
        return Result.completed(getHeartbeats())

      database.removeTabHeartbeats = (tabIds) ->
        database.mustBeInTransaction()
        heartbeats = getHeartbeats()
        for tabId in tabIds
          delete heartbeats[tabId]
        setHeartbeats heartbeats
        return Result.completed()


Tabs that respond to a ping broadcast.

      getTabAlives = ->
        JSON.parse(Sim.databaseData.tabAlives)

      setTabAlives = (alives) ->
        Sim.databaseData.tabAlives = stringify(alives)
        return

      database.readTabAlives = ->
        database.mustBeInTransaction()
        return Result.completed(getTabAlives())

      database.writeTabAlive = (tabId, timestamp) ->
        database.mustBeInTransaction()
        alives = getTabAlives()
        alives[tabId] = timestamp
        setTabAlives alives
        return Result.completed()

      database.removeTabAlives = (tabIds) ->
        database.mustBeInTransaction()
        alives = getTabAlives()
        for tabId in tabIds
          delete alives[tabId]
        setTabAlives alives
        return Result.completed()


The proxy tab.

      getProxyTab = ->
        JSON.parse(Sim.databaseData.proxyTab)

      setProxyTab = (tabId) ->
        Sim.databaseData.proxyTab = stringify(tabId)
        Sim.databaseChanged()
        return

      database.writeProxyTab = (tabId) ->
        database.mustBeInTransaction()
        setProxyTab tabId
        return Result.completed()

      database.readProxyTab = ->
        database.mustBeInTransaction()
        return Result.completed(getProxyTab())


The list of subscriptions that a tab is subscribed to.  A tab
subscription is uniquely identified by (tabId, subscription name,
subscription arguments).

      mergeSubscriptions = (tabSubscriptions) ->
        merged = []
        for {tabId, name, args} in tabSubscriptions
          subscription = {name, args}
          unless _.find(merged, (s) -> EJSON.equals(s, subscription))
            merged.push subscription
        return merged

      getTabSubscriptions = ->
        JSON.parse(Sim.databaseData.tabSubscriptions)

      getMergedSubscriptions = ->
        mergeSubscriptions(getTabSubscriptions())

      setTabSubscriptions = (tabSubscriptions) ->
        Sim.databaseData.tabSubscriptions = stringify(tabSubscriptions)
        Sim.databaseChanged()
        return

      database.addTabSubscription = (tabSubscription) ->
        database.mustBeInTransaction()
        tabSubscriptions = getTabSubscriptions()
        unless _.find(tabSubscriptions, (s) -> EJSON.equals(s, tabSubscription))
          tabSubscriptions.push tabSubscription
        setTabSubscriptions tabSubscriptions
        return Result.completed()

      database.readTabSubscriptions = ->
        database.mustBeInTransaction()
        return Result.completed(getTabSubscriptions())

      database.readMergedSubscriptions = ->
        database.mustBeInTransaction()
        return Result.completed(getMergedSubscriptions())

      database.removeTabSubscription = (tabSubscription) ->
        database.mustBeInTransaction()
        tabSubscriptions = _.reject(
          getTabSubscriptions(),
          (s) -> EJSON.equals(s, tabSubscription)
        )
        setTabSubscriptions tabSubscriptions
        clearUnusedSubscriptions()
        return Result.completed()

      database.removeSubscriptionsOfTabs = (tabIds) ->
        database.mustBeInTransaction()
        tabSubscriptions = _.reject(
          getTabSubscriptions(),
          ({tabId}) -> tabId in tabIds
        )
        setTabSubscriptions tabSubscriptions
        clearUnusedSubscriptions()
        return Result.completed()

Information about subscriptions, this time across all tabs: the key
is (subscription name, subscription arguments).

      getSubscriptions = ->
        JSON.parse(Sim.databaseData.subscriptions)

      setSubscriptions = (subscriptions) ->
        Sim.databaseData.subscriptions = stringify(subscriptions)
        Sim.databaseChanged()
        return

      database.ensureSubscription = (subscription) ->
        database.mustBeInTransaction()
        serialized = serialize(subscription)
        subscriptions = getSubscriptions()
        unless subscriptions[serialized]?
          subscriptions[serialized] = {
            readyFromServer: false
            ready: false
          }
          setSubscriptions subscriptions
        return Result.completed()

      database.haveSubscription = (subscription) ->
        database.mustBeInTransaction()
        serialized = serialize(subscription)
        subscriptions = getSubscriptions()
        haveSubscription = subscriptions[serialized]?
        return Result.completed(haveSubscription)

      database.setSubscriptionReadyFromServer = (subscription) ->
        database.mustBeInTransaction()
        serialized = serialize(subscription)
        subscriptions = getSubscriptions()
        record = subscriptions[serialized]
        if record?
          record.readyFromServer = true
          setSubscriptions subscriptions
        return Result.completed()

      database.setSubscriptionReady = (serialized) ->
        database.mustBeInTransaction()
        subscriptions = getSubscriptions()
        record = subscriptions[serialized]
        if record?
          record.ready = true
          setSubscriptions subscriptions
        return Result.completed()

      database.readSubscriptions = ->
        database.mustBeInTransaction()
        return Result.completed(getSubscriptions())

      clearUnusedSubscriptions = ->
        mergedSubscriptions = (serialize(subscription) for subscription in getMergedSubscriptions())
        subscriptions = getSubscriptions()
        toRemove = []
        for subscription of subscriptions
          unless subscription in mergedSubscriptions
            toRemove.push subscription
        delete subscriptions[key] for key in toRemove
        setSubscriptions subscriptions
        return

Keep track of which methods had local writes (stub documents) at the
time a new subscription was subscribed to.  These methods are "holding
up" the subscription being ready (a subscription doesn't become ready
until previous local writes have been flushed, but writes after
subscribing to the subscription don't matter).

      getMethodsHoldingUpSubs = ->
        JSON.parse(Sim.databaseData.methodsHoldingUpSubs)

      setMethodsHoldingUpSubs = (methodsHoldingUpSubs) ->
        Sim.databaseData.methodsHoldingUpSubs = stringify(methodsHoldingUpSubs)
        Sim.databaseChanged()
        return

      database.addSubscriptionWaitingOnMethods = (subscription, methodIds) ->
        database.mustBeInTransaction()
        serialized = serialize(subscription)
        holdingUp = getMethodsHoldingUpSubs()
        for methodId in methodIds
          list = (holdingUp[methodId] or= [])
          list.push(serialized) unless _.contains(list, serialized)
        setMethodsHoldingUpSubs holdingUp
        return Result.completed()

      database.removeMethodHoldingUpSubs = (methodId) ->
        database.mustBeInTransaction()
        holdingUp = getMethodsHoldingUpSubs()
        delete holdingUp[methodId]
        setMethodsHoldingUpSubs holdingUp
        return Result.completed()

      database.readSubsHeldUp = ->
        database.mustBeInTransaction()
        subsHeldUp = {}
        holdingUp = getMethodsHoldingUpSubs()
        for methodId, subs of holdingUp
          for sub in subs
            subsHeldUp[sub] = true
        return Result.completed(_.keys(subsHeldUp))


A queue of recent updates.  This allows a tab to quickly catch up and
ensure that it has the latest data at the beginning of a transaction.
We can also easily ensure processing updates in a specific order (such
as updating documents and then marking a subscription as ready).

Each tab has a pointer into the queue to keep track of which updates
it has already applied.  Updates are removed from the queue once all
tabs have processed an update.  Dead tabs have their pointer removed
(which in turn can free up old updates to be removed when all
remaining pointers have gone past the update).

      getUpdateCount = ->
        JSON.parse(Sim.databaseData.updateCount)

      setUpdateCount = (updateCount) ->
        Sim.databaseData.updateCount = updateCount
        Sim.databaseChanged()
        return

      getUpdates = ->
        JSON.parse(Sim.databaseData.updates)

      setUpdates = (updates) ->
        Sim.databaseData.updates = stringify(updates)
        Sim.databaseChanged()
        return

      getTabUpdatePointers = ->
        JSON.parse(Sim.databaseData.tabUpdatePointers)

      setTabUpdatePointers = (tabUpdatePointers) ->
        Sim.databaseData.tabUpdatePointers = stringify(tabUpdatePointers)
        Sim.databaseChanged()
        return

      database.addUpdate = (update) ->
        database.mustBeInTransaction()
        updateCount = getUpdateCount()
        updates = getUpdates()
        update = EJSON.clone(update)
        update.index = updateCount
        updates.push update
        ++updateCount
        setUpdateCount updateCount
        setUpdates updates
        return Result.completed()

      database.initializeTabUpdateIndex = (tabId) ->
        database.mustBeInTransaction()
        updateCount = getUpdateCount()
        pointers = getTabUpdatePointers()
        pointers[tabId] = updateCount
        setTabUpdatePointers pointers
        return Result.completed()

      database.removeTabUpdateIndexesForTabs = (tabIds) ->
        database.mustBeInTransaction()
        pointers = getTabUpdatePointers()
        for tabId in tabIds
          delete pointers[tabId]
        setTabUpdatePointers pointers
        return Result.completed()

      database.removeProcessedUpdates = ->
        database.mustBeInTransaction()
        pointers = getTabUpdatePointers()
        updates = getUpdates()
        toRemove = 0
        for update in updates
          remove = true
          for tabId, index of pointers
            remove = false if index <= update.index
          if remove
            ++toRemove
          else
            break
        while toRemove-- > 0
          updates.shift()
        setUpdates updates
        return Result.completed()

      database.pullUpdatesForTab = (tabId) ->
        database.mustBeInTransaction()
        updates = getUpdates()
        pointers = getTabUpdatePointers()
        count = getUpdateCount()

        index = pointers[tabId]
        return Result.completed([]) unless index?
        result = _.filter(updates, (update) -> update.index >= index)
        pointers[tabId] = count

        setTabUpdatePointers pointers
        setUpdateCount count

        return Result.completed(result)
