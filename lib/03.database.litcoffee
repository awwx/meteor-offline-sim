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
        docs:          '{}'
        stubDocuments: '{}'
        queuedMethods: '{}'
        subscriptions: '[]'
        activeTab:     'null'
        tabHeartbeats: '{}'
      }

Don't include the tab heartbeats in the dump because they change
constantly.

      Sim.dumpDatabase = ->
        databaseDep.depend()
        data = Sim.databaseData
        return (
          """
          activeTab: #{data.activeTab}

          subscriptions: #{data.subscriptions}

          queuedMethods: #{data.queuedMethods}

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


The "active tab".

      getActiveTab = ->
        JSON.parse(Sim.databaseData.activeTab)

      setActiveTab = (tabId) ->
        Sim.databaseData.activeTab = stringify(tabId)
        Sim.databaseChanged()
        return

      database.writeActiveTab = (tabId) ->
        database.mustBeInTransaction()
        setActiveTab tabId
        return Result.completed()

      database.readActiveTab = ->
        database.mustBeInTransaction()
        return Result.completed(getActiveTab())


The list of subscriptions that we've subscribed to.

      getSubscriptions = ->
        JSON.parse(Sim.databaseData.subscriptions)

      setSubscriptions = (subscriptions) ->
        Sim.databaseData.subscriptions = stringify(subscriptions)
        Sim.databaseChanged()
        return

      database.addSubscription = (subscription) ->
        database.mustBeInTransaction()
        subscriptions = getSubscriptions()
        subscriptions.push subscription
        setSubscriptions subscriptions
        return Result.completed()

      database.readSubscriptions = ->
        database.mustBeInTransaction()
        return Result.completed(getSubscriptions())
