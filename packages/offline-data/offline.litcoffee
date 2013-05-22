# Offline #

This offline approach creates an "offline connection", which wraps the
livedata connection.  When the developer opens an "offline
collection", a Meteor.Collection is created, munged to use the offline
connection instead of the regular livedata connection.  The
OfflineConnection then provides its own implementation for running
method stubs.


## Server ##

    if Meteor.isServer

This allows us to invoke a method on the server without running the
stub on the client.  (We've already run the stub using the offline
algorithm).

      Meteor.methods
        'awwx.Offline.apply': (methodId, name, params) ->
          return Meteor.apply name, params


On the server, Offline.methods etc. simply delegate to their Meteor
counterpart.

      Offline = (@Offline or= {})

      Offline.methods = (methods) ->
        Meteor.methods methods

      Offline.openCollection = (args...) ->
        new Meteor.Collection(args...)


## Client App ##

    return unless Meteor.isClient and isApp

    {Result} = Sim ? awwx

    Offline = (@Offline or= {})

    serialize = canonicalStringify

    initialized = new Result()

    database.transaction(thisApp, 'initialize', ->
      Result.join([
        database.initializeTabUpdateIndex(thisTabId)
        database.readDocs()
        database.readSubscriptions()
      ])
    )
    .then(([ignore, collectionDocs, subscriptions]) ->
      for collectionName, docs of collectionDocs
        for docId, doc of docs
          updateLocal collectionName, docId, doc

      for serialized, record of subscriptions
        if record.ready
          setSubscriptionReady serialized, true

      initialized.complete()
      return
    )


An offline subscription is ready when:

* the underlying Meteor subscription is ready

* server documents have been stored in the database

* database documents have been copied to the local collection

    subscriptionReadyDeps = {}
    subscriptionReady = {}

    @getSubscriptionReady = (subscription) ->
      serialized = serialize(subscription)
      dep = (subscriptionReadyDeps[serialized] or= new Deps.Dependency)
      dep.depend()
      unless subscriptionReady[serialized]?
        subscriptionReady[serialized] = false
      return subscriptionReady[serialized]

    setSubscriptionReady = (serializedSubscription, ready) ->
      dep = (subscriptionReadyDeps[serializedSubscription] or= new Deps.Dependency)
      if subscriptionReady[serializedSubscription] isnt ready
        subscriptionReady[serializedSubscription] = ready
        dep.changed()
      return


Read which subscriptions are ready from the database and update our
reactive data source.  A subscription will only transition from not
ready to ready while we're subscribed to it.  Subscriptions not in the
database are considered not ready, so if we stop subscribing and no
other tabs are subscribed then a subscription can become not ready
again.

Subscriptions become ready when they are ready from the server and
they don't have methods holding them up.

TODO set subscriptions not ready which no longer have any subscribers.

        # # subscriptions not in the database
        # for serialized, ready of subscriptionReady
        #   if serialized not of subscriptions
        #     setSubscriptionReady serialized, false

    updateSubscriptionsReadyInTransaction = ->
      database.mustBeInTransaction()
      Result.join([
        database.readSubscriptions()
        database.readSubsHeldUp()
      ])
      .then(([subscriptions, subscriptionsHeldUp]) ->
        newlyReady = []
        for serialized, {readyFromServer, ready} of subscriptions
          if not ready and readyFromServer and serialized not in subscriptionsHeldUp
            newlyReady.push serialized
        if newlyReady.length is 0
          return false
        writes = []
        for serialized in newlyReady
          writes.push database.setSubscriptionReady(serialized)
          writes.push database.addUpdate {update: 'subscriptionReady', subscription: JSON.parse(serialized)}
        Result.join(writes)
        .then(-> return true)
      )

    updateSubscriptionsReady = ->
      database.transaction(thisApp, 'update subscriptions ready', ->
        updateSubscriptionsReadyInTransaction()
      ).then((someNewlyReady) ->
        if someNewlyReady
          broadcast 'update'
      )
      return

    addNewSubscriptionToDatabase = (name, args) ->
      database.mustBeInTransaction()
      database.readOutstandingMethodsWithStubDocuments()
      .then((methodIds) ->
        database.addSubscriptionWaitingOnMethods({name, args}, methodIds)
      )
      .then(->
        database.ensureSubscription({name, args})
      )

    addTabSubscriptionToDatabase = (name, args) ->
      database.transaction(thisApp, 'add subscription', ->
        return Result.join([
          database.addTabSubscription({tabId: thisTabId, name, args})
          database.haveSubscription({name, args})
        ])
        .then((ignore, haveSubscription) ->
          if haveSubscription
            return
          else
            return addNewSubscriptionToDatabase name, args
        )
      ).then(->
        broadcast 'subscriptionsUpdated'
      )

Add to this tab's list of offline subscriptions.

TODO callback when subscription is ready, and the `stop()` method to
cancel the subscription.

"ready" means we've finished loading saved data from the browser
database, or, if this is a first subscription and we don't have data in
the database yet, that we've finished loaded data from the server (the
underlying server subscription is ready).

TODO support `onError` (will need to store error in database)

    Offline.subscribe = (name, args...) ->

      last = _.last(args)
      if _.isFunction(last)
        args = _.initial(args)
        onReady = last
        onError = (->)
      else if last? and (_.isFunction(last.onReady) or _.isFunction(last.onError))
        args = _.initial(args)
        onReady = last.onReady ? (->)
        onError = last.onError ? (->)
      else
        onReady = (->)
        onError = (->)

      if Deps.active
        throw new Error(
          'reactive offline subscriptions are not yet implemented'
        )

      addTabSubscriptionToDatabase name, args

      stopped = false

      handle = {
        ready: ->
          if stopped
            return false
          else
            return getSubscriptionReady({name, args})

        stop: ->
          return if stopped
          stopped = true
          database.transaction(thisApp, 'remove tab subscription', ->
            database.removeTabSubscription({tabId: thisTabId, name, args})
          ).then(->
            Meteor.defer -> broadcast 'subscriptionsUpdated'
          )
          return
      }

      computation = Deps.autorun ->
        if handle.ready()
          onReady()
          computation.stop()
        return

      return handle


The list of Meteor subscriptions that we've subscribed when we're the
proxy tab.

    meteorSubscriptionHandles = {}
    nMeteorSubscriptionsReady = 0

    alreadyHaveMeteorSubscription = (subscription) ->
      !! meteorSubscriptionHandles[canonicalStringify(subscription)]

    allMeteorSubscriptionsReady = ->
      nMeteorSubscriptionsReady is _.size(meteorSubscriptionHandles)


We are the proxy tab and all our subscriptions are ready.  We can now
delete documents in the offline collection which are no longer present
on the server.

    deletedRemovedDocs = false

    deleteRemovedDocuments = ->
      database.mustBeInTransaction()
      if deletedRemovedDocs
        return Result.completed()
      else
        deletedRemovedDocs = true
        return forEachCollectionResult('deleteDocumentsGoneFromServer')

    checkIfReadyToDeleteDocs = ->
      database.transaction(thisApp, 'all subscriptions ready', ->
        database.readProxyTab()
        .then((proxyTabId) =>
          if proxyTabId is thisTabId and allMeteorSubscriptionsReady()
            deleteRemovedDocuments()
        )
      )
      .then(->
        broadcast 'update'
      )
      return

    meteorSubscriptionReady = (subscription) ->
      database.transaction(thisApp, 'subscription ready', ->
        database.readProxyTab()
        .then((proxyTabId) ->
          if proxyTabId is thisTabId
            return database.setSubscriptionReadyFromServer(subscription)
          else
            return
        ).then(->
          updateSubscriptionsReadyInTransaction()
        )
      ).then(->
        broadcast 'update'
      )
      return

    updateSubscriptions = ->
      # all tabs update their knowledge of which subscriptions are ready
      updateSubscriptionsReady()

      # only the proxy tab subscribes to the Meteor subscription
      database.transaction(thisApp, 'subscribe to subscriptions', ->
        Result.join([
          database.readMergedSubscriptions()
          database.readProxyTab()
        ])
      )
      .then(([subscriptions, proxyTabId]) ->
        return unless proxyTabId is thisTabId

        for serializedSubscription, handle of meteorSubscriptionHandles
          subscription = JSON.parse(serializedSubscription)
          unless _.find(subscriptions, (s) -> EJSON.equals(s, subscription))
            handle.stop()
            delete meteorSubscriptionHandles[serializedSubscription]

        for subscription in _.reject(subscriptions, alreadyHaveMeteorSubscription)
          do (subscription) ->
            deletedRemovedDocs = false
            {name, args} = subscription
            handle = Meteor.subscribe name, args..., ->
              meteorSubscriptionReady(subscription)
              ++nMeteorSubscriptionsReady
              checkIfReadyToDeleteDocs()
              return
            meteorSubscriptionHandles[canonicalStringify(subscription)] = handle
            return

        return
      )
      return


A tab only subscribes to the shared subscriptions when it is the proxy
tab.

    broadcast.listen 'subscriptionsUpdated', ->
      updateSubscriptions()

    nowProxy.listen ->
      updateSubscriptions()

    tabsAreDead.listen ->
      updateSubscriptions()


When some other tab becomes the proxy tab we won't be paying attention
to updates from the server, so we don't need to stay subscribed
ourselves.

    noLongerProxy.listen ->
      for subscription, handle of meteorSubscriptionHandles
        handle.stop()
      meteorSubscriptionHandles = {}
      nMeteorSubscriptionsReady = 0
      return


    copyServerToDatabase = (collectionName, docId) ->
      return offlineCollections[collectionName].copyServerToDatabase(docId)


TODO no longer proxy tab

    methodCompleted = (methodId) ->
      database.transaction(thisApp, 'method completed', ->
        database.readProxyTab()
        .then((proxyTabId) ->
          return unless proxyTabId is thisTabId
          database.removeQueuedMethod(methodId)
          .then(-> database.removeDocumentsWrittenByStub(methodId))
          .then((documentsNowFree) ->
            writes = []
            for {collectionName, docId} in documentsNowFree
              writes.push copyServerToDatabase(collectionName, docId)
            return Result.join(writes)
          )
          .then(->
            database.removeMethodHoldingUpSubs(methodId)
          )
          .then(->
            updateSubscriptionsReady()
          )
        )
      )
      .then(->
        broadcast 'update'
      )
      return


We only need to ask Meteor to send a method once in our process
because Meteor will automatically retry as long as we're alive.

A mapping of `methodId -> true` for methods in the database list of
queued methods that *this* tab has sent.  (I don't bother to clear
the entry in `methodsSent` when the method completes because the
mapping gets reset on each call to `sendQueuedMethods` anyway).

    methodsSent = {}

Make a method call.  `awwx.Offline.apply` on the server simply runs
the method, so this has the same effect as calling `Meteor.apply(name,
args)`, except that we *don't* invoke the stub for the method.

Problem: Meteor will automatically retry sending method calls from a
tab until it goes online again.  So once a method call has been queued
up in a tab, it will eventually be sent if the app goes online.  So if
in iOS we change the proxy tab to whichever tab is active, we can
easily end up with multiple tabs all sending the same message.

TODO can we hack livedata_connection to abort sending messages?


    sendQueuedMethod = (methodId, name, args) ->
      return if methodsSent[methodId]
      args = EJSON.parse(args)
      Meteor.call 'awwx.Offline.apply', methodId, name, args, (error, result) ->
        if error
          Meteor._debug 'offline method error', name, error
        methodCompleted(methodId)
        return
      return


TODO Also support other Livedata connections.
Perhaps keyed by URL (e.g. "madewith.meteor.com")?
Is the URL available from the LivedataConnection?

TODO argument for which connection

    broadcast.listen 'newQueuedMethod', ->
      defaultOfflineConnection.sendQueuedMethods()
      return

    nowProxy.listen ->
      defaultOfflineConnection.sendQueuedMethods()
      return


    methodHandlers = {}


    class OfflineConnection

      constructor: (@realConnection) ->
        if Meteor.isServer
          throw new Error('an OfflineConnection is client only')
        @methodHandlers = {}
        @_stores = {}

      registerStore: (name, wrappedStore) ->
        return wrappedStore

      addBrowserCollection: (name, browserCollection) ->
        @_browserCollections[name] = browserCollection

      userId: ->
        @realConnection.userId()

      setUserId: (userId) ->
        @realConnection.setUserId(userId)


https://github.com/meteor/meteor/blob/release/0.6.1/packages/livedata/livedata_connection.js#L525

      methods: (methods) ->
        _.each methods, (func, name) =>
          if @methodHandlers[name]
            throw new Error("A method named '" + name + "' is already defined")
          @methodHandlers[name] = func
        return


Send any queued methods listed in the database that haven't been sent
from this tab yet.

TODO this code currently only sends queued methods after a method call
has been made in this tab.  If we polled we could send a method that
another tab queued up and died before it had a chance to send it.  But
we'll send the other tab's method anyway the next time we have our own
method to send.

TODO probably need to check if we're already sending queued methods.
(Another method call could be made while we're waiting for the
transaction).

TODO the queued methods should be ordered so that we send them in the
order that they were called.

TODO only send queued methods from the proxy tab

      sendQueuedMethods: ->
        database.transaction(thisApp, 'send queued methods', ->
          Result.join([
            database.readProxyTab()
            database.readQueuedMethods()
          ])
        )
        .then(([proxyTabId, methods]) ->
          return unless proxyTabId is thisTabId
          sent = {}
          for methodId, {name, args} of methods
            sendQueuedMethod(methodId, name, args)
            sent[methodId] = true
          methodsSent = sent
        )
        return

TODO not sure how it would interact if a offline method stub calls a
regular method stub or vice versa.


https://github.com/meteor/meteor/blob/release/0.6.1/packages/livedata/livedata_connection.js#L584

      _runStub: (methodId, alreadyInSimulation, name, args) ->
        stub = @methodHandlers[name]
        return unless stub

TODO sessionData: use the same sessionData as the real connection or our own?

        invocation = new Meteor._MethodInvocation({
          isSimulation: true
          userId: @userId()
          setUserId: (userId) => @setUserId(userId)
        })

        if alreadyInSimulation
          try
            ret = Meteor._CurrentInvocation.withValue(invocation, ->
              return stub.apply(invocation, EJSON.clone(args))
            )
          catch e
            exception = e
          if exception
            return Result.failed(exception)
          else
            return Result.completed(ret)

        database.transaction(thisApp, 'run method stub', =>
          processUpdatesInTransaction()
          .then(=>
            saveOriginals()
            try
              ret = Meteor._CurrentInvocation.withValue(invocation, ->
                return stub.apply(invocation, EJSON.clone(args))
              )
            catch e
              exception = e
            return writeChanges(methodId)
          )
        )
        .then(=>
          broadcast 'update'
          if exception
            return Result.failed(exception)
          else
            return Result.completed(ret)
        )


https://github.com/meteor/meteor/blob/release/0.6.1/packages/livedata/livedata_connection.js#L534

      call: (name, args...) ->
        if args.length and typeof args[args.length - 1] is 'function'
          callback = args.pop()
        return @apply(name, args, callback)


https://github.com/meteor/meteor/blob/release/0.6.1/packages/livedata/livedata_connection.js#L543

      apply: (name, args, options, callback) ->
        if not callback and typeof options is 'function'
          callback = options
          options = {}

        if callback
          callback = Meteor.bindEnvironment callback, (e) ->
            Meteor._debug("Exception while delivering result of invoking '" +
                          name + "'", e, e.stack)

        methodId = Random.id()

        enclosing = Meteor._CurrentInvocation.get()
        alreadyInSimulation = enclosing and enclosing.isSimulation

        @_runStub(methodId, alreadyInSimulation, name, args)
        .onFailure((exception) =>
          unless exception.expected
            Meteor._debug(
              "Exception while simulating the effect of invoking '" +
              name + "'", exception, exception.stack
            )
          return
        )
        .always(=>
          return if alreadyInSimulation
          database.transaction(thisApp, 'add queued method', =>
            database.addQueuedMethod(methodId, name, EJSON.stringify(args))
          )
          .then(=>
            broadcast 'newQueuedMethod'
            return
          )
        )

        return


    @defaultOfflineConnection = new OfflineConnection(Meteor.default_connection)

    Offline._offlineCollections = offlineCollections = {}

    Offline.methods = (methods) ->
      defaultOfflineConnection.methods methods

    Offline.call = (args...) ->
      defaultOfflineConnection.call args...

    Offline.apply = (args...) ->
      defaultOfflineConnection.apply args...

    Meteor.startup ->
      defaultOfflineConnection.sendQueuedMethods()


    localCollections = {}

    getLocalCollection = (collectionName) ->
      localCollections[collectionName] or= new LocalCollection()

    updateLocal = (collectionName, docId, doc) ->
      localCollection = getLocalCollection(collectionName)
      if doc?
        if doc._id isnt docId
          throw new Error("oops, document id doesn't match")
        if localCollection.findOne(docId)?
          localCollection.update(docId, doc)
        else
          localCollection.insert(doc)
      else
        localCollection.remove(docId)
      return


    class OfflineCollection

      constructor: (@name, @serverCollection) ->
        if Meteor.isServer
          throw new Error('client only')

        if offlineCollections[@name]?
          throw new Error(
            "already constructed an offline collection for: #{name}"
          )
        offlineCollections[@name] = this

        @localCollection = getLocalCollection(@name)
        @connection = defaultOfflineConnection

        driver =
          open: (_name) =>
            unless _name is @name
              throw new Error(
                "oops, driver is being called with the wrong name
                 for this collection: #{_name}"
              )
            return @localCollection

        @collection = new Meteor.Collection(
          @name,
          {manager: @connection, _driver: driver}
        )

        @watchServer()


A document has changed in the server collection (the local client
mirror of our subscriptions to the server).

Ignore updates from the server if this tab isn't the proxy tab (this
tab's livedata connection isn't necessarily exactly in sync with the
proxy tab's connection).

We also defer updating if the document has been written by a stub of a
method still in flight.

      serverDocUpdated: (docId, doc) ->
        database.transaction(thisApp, 'server doc changed', =>
          Result.join([
            database.wasDocumentWrittenByStub(@name, docId)
            database.readProxyTab()
          ])
          .then(([wasWritten, proxyTabId]) =>
            if proxyTabId isnt thisTabId or wasWritten
              return
            else
              (if doc?
                database.writeDoc @name, doc
              else
                database.deleteDoc @name, docId
              ).then(=>
                database.addUpdate {update: 'documentUpdated', name: @name, docId, doc}
              )
          )
        )
        .then(=>
          broadcast 'update'
        )
        return


      watchServer: ->
        @serverCollection.find().observe
          added:   (doc) => @serverDocUpdated doc._id, doc
          changed: (doc) => @serverDocUpdated doc._id, doc
          removed: (doc) => @serverDocUpdated doc._id, null
        return


TODO some duplicate code with writeMethodChanges in addUpdate, and
calling findOne twice on the serverCollection.

      copyServerToDatabase: (docId) ->
        database.mustBeInTransaction()
        return Result.join([
          writeDoc(@name, @serverCollection, docId)
          database.addUpdate({update: 'documentUpdated', name: @name, docId, doc: @serverCollection.findOne(docId)})
        ])


We have a full and complete set of data from the server (our
subscriptions are ready).  We can now delete documents in the offline
collection which are no longer present on the server.

      deleteDocUnlessWrittenByStub: (docId) ->
        database.mustBeInTransaction()
        database.wasDocumentWrittenByStub(@name, docId)
        .then((wasWritten) =>
          if wasWritten
            return
          else
            database.deleteDoc(@name, docId)
            .then(=>
              database.addUpdate {update: 'documentUpdated', name: @name, docId}
            )
        )

      deleteDocumentsGoneFromServer: ->
        database.mustBeInTransaction()
        processUpdatesInTransaction()
        .then(=>
          idsToDelete = []
          @localCollection.find({}).forEach (doc) =>
            unless @serverCollection.findOne(doc._id)
              idsToDelete.push doc._id
          # TODO Result.map ?
          writes = []
          for docId in idsToDelete
            writes.push @deleteDocUnlessWrittenByStub(docId)
          return Result.join(writes)
        )

TODO maybe rename "name" to "collection"

      writeMethodChanges: (methodId) ->
        database.mustBeInTransaction()
        originals = @localCollection.retrieveOriginals()
        writes = []
        for docId of originals
          writes.push writeDoc(@name, @localCollection, docId)
          writes.push database.addDocumentWrittenByStub(methodId, @name, docId)
          writes.push database.addUpdate {update: 'documentUpdated', name: @name, docId, doc: @localCollection.findOne(docId)}
        return Result.join(writes)

For each offline collection, call the method `methodName` on that
collection.  Return a mapping of collection name to the return value
of calling the method on that collection.

    forEachCollection = (methodName, args...) ->
      ret = []
      for collectionName, offlineCollection of offlineCollections
        method = offlineCollection[methodName]
        unless method?
          throw new Error(
            "offline collection has no method named: #{methodName}"
          )
        ret[collectionName] = method.apply(offlineCollection, args)
      return ret

    forEachCollectionResult = (methodName, args...) ->
      r = forEachCollection(methodName, args...)
      return Result.join(_.values(r))

    saveOriginals = ->
      for name, offlineCollection of offlineCollections
        offlineCollection.localCollection.saveOriginals()
      return

`collection` can be our localCollection or serverCollection, depending
on the source of the document we're writing.

TODO should every `writeDoc` also add the update to the database?

    writeDoc = (name, collection, docId) ->
      doc = collection.findOne(docId)
      if doc?
        return database.writeDoc name, doc
      else
        return database.deleteDoc name, docId

    writeChanges = (methodId) ->
      database.mustBeInTransaction()
      r = forEachCollectionResult('writeMethodChanges', methodId)
      return r


TODO what if we just wrote to the document in a stub?

    processDocumentUpdated = (update) ->
      {name, docId, doc} = update
      updateLocal name, docId, doc
      return

    processSubscriptionReady = (update) ->
      {subscription} = update
      setSubscriptionReady serialize(subscription), true
      return

    processUpdate = (update) ->
      switch update.update
        when 'documentUpdated'   then processDocumentUpdated(update)
        when 'subscriptionReady' then processSubscriptionReady(update)
        else
          throw new Error "unknown update: " + serialize(update)
      return

    processUpdatesInTransaction = ->
      database.mustBeInTransaction()
      database.pullUpdatesForTab(thisTabId)
      .then((updates) ->
        database.removeProcessedUpdates()
        .then(->
          processUpdate(update) for update in updates
          return
        )
      )

    processUpdates = ->
      database.transaction(thisApp, 'process updates', ->
        database.pullUpdatesForTab(thisTabId)
        .then((updates) ->
          database.removeProcessedUpdates()
          .then(->
            return updates
          )
        )
      )
      .then((updates) ->
        processUpdate(update) for update in updates
        return
      )
      return


    broadcast.listen 'update', processUpdates


Currently return a Meteor.Collection as our offline collection (munged
internally to use the "offline" connection)... but the API will have
to change to support getting the results of calling methods.

    Offline.wrapCollection = (serverCollection) ->
      return (new OfflineCollection(
        serverCollection._name,
        serverCollection)
      ).collection


TODO `new Offline.Collection`

    Offline.openCollection = (name) ->
      Offline.wrapCollection(new Meteor.Collection(name))
