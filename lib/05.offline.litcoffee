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


## Client App ##

    return unless Meteor.isClient and isApp

    {Result} = Sim

    Offline = (@Offline or= {})


Add to our list of offline subscriptions.

TODO callback when subscription is ready, and the `stop()` method to
cancel the subscription.

    Offline.subscribe = (name, args...) ->
      if Deps.active
        throw new Error(
          'reactive offline subscriptions are not yet implemented'
        )

      subscription = {name, args}

      database.transaction(thisApp, 'add subscription', ->
        database.readSubscriptions()
        .then((subscriptions) ->
          unless hasSubscription(subscriptions, subscription)
            database.addSubscription(subscription)
        )
      ).then(->
        broadcast 'subscriptionAdded'
      )

The list of subscriptions that we've already subscribed to in this
tab.

    subscribedTo = []

    stringify = JSON.stringify

    hasSubscription = (list, subscription) ->
      _.some(list, (sub) -> EJSON.equals(subscription, sub))

    alreadyHaveSubscription = (subscription) ->
      hasSubscription(subscribedTo, subscription)

    subscribeToSubscriptions = ->
      database.transaction(thisApp, 'subscribe to subscriptions', ->
        database.readSubscriptions()
      )
      .then((subscriptions) ->
        for {name, args} in _.reject(subscriptions, alreadyHaveSubscription)
          Meteor.subscribe name, args...
      )
      return

Right now all tabs subscribe to all subscriptions.  But tabs
could unsubscribe if another tab becomes the proxy tab.

    broadcast.listen 'subscriptionAdded', ->
      subscribeToSubscriptions()

    copyServerToLocal = (collectionName, docId) ->
      return offlineCollections[collectionName].copyServerToLocal(docId)


    methodCompleted = (methodId) ->
      database.transaction(thisApp, 'method completed', ->
        database.removeQueuedMethod(methodId)
        .then(-> database.removeDocumentsWrittenByStub(methodId))
        .then((documentsNowFree) ->
          writes = []
          for {collectionName, docId} in documentsNowFree
            writes.push copyServerToLocal(collectionName, docId)
          return Result.join(writes)
        )
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

We may successfully run the method on the server but `methodCompleted`
might not get called if the browser tab is closed, or if we lose the
Internet connection before we get the reply back.

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

    methodHandlers = {}


https://github.com/meteor/meteor/blob/release/0.6.1/packages/livedata/livedata_connection.js#L534

    Offline.call = (name, args...) ->
      if args.length and typeof args[args.length - 1] is 'function'
        callback = args.pop()
      return Offline.apply(name, args, callback)


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

      sendQueuedMethods: ->
        database.transaction(thisApp, 'send queued methods', ->
          database.readQueuedMethods()
        )
        .then((methods) ->
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

TODO userId, setUserId: anything special we'd need to do with offline data?

TODO sessionData: use the same sessionData as the real connection or our own?

        invocation = new Meteor._MethodInvocation({
          isSimulation: true
        })

TODO fixme

        if alreadyInSimulation
          try
            ret = Meteor._CurrentInvocation.withValue(invocation, ->
              return stub.apply(invocation, EJSON.clone(args))
            )
          catch e
            exception = e
          return Result.completed({ret, exception})

        database.transaction(thisApp, 'run method stub', =>
          reloadAll()
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
          if exception
            return Result.failed(exception)
          else
            return Result.completed(ret)
        )


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

        if alreadyInSimulation
          throw new Error('not implemented yet')

        @_runStub(methodId, alreadyInSimulation, name, args)
        .then(=>
          database.transaction(thisApp, 'add queued method', =>
            database.addQueuedMethod(methodId, name, EJSON.stringify(args))
          )
        )
        .then(=>
          Meteor.defer(=> @sendQueuedMethods())
          return
        )

        return

        # if exception and not exception.expected
        #   Meteor._debug("Exception while simulating the effect of invoking '" +
        #                 name + "'", exception, exception.stack)

        # callback = (->) unless callback


    return unless isApp

    offlineConnection = new OfflineConnection(Meteor.default_connection)

    Offline._offlineCollections = offlineCollections = {}


    Meteor.startup ->
      offlineConnection.sendQueuedMethods()


TODO Need to do explicit subscriptions, and to only subscribe from one
tab at a time.

TODO Figure out how to munge the `autopublish` package.

    class OfflineCollection

      constructor: (@name) ->
        if Meteor.isServer
          throw new Error('client only')

        if offlineCollections[@name]?
          throw new Error(
            "already constructed an offline collection for: #{name}"
          )
        offlineCollections[@name] = this

        @serverCollection = new Meteor.Collection(@name)
        @localCollection = new LocalCollection()
        @connection = offlineConnection

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

        database.transaction(thisApp, 'initial load from database', =>
          @loadFromDatabase()
        )
        .then(=> @watchServer())

      serverDocChanged: (doc) ->
        database.transaction(thisApp, 'server doc changed', =>
          database.wasDocumentWrittenByStub(@name, doc._id)
          .then((wasWritten) =>
            if wasWritten
              return
            else
              return database.writeDoc @name, doc
          )
        )
        .then(=>
          broadcast 'documentUpdated', @name, doc._id
        )
        return

      serverDocRemoved: (doc) ->
        database.transaction(thisApp, 'server doc removed', =>
          database.wasDocumentWrittenByStub(@name, doc._id)
          .then((wasWritten) =>
            if wasWritten
              return
            else
              return database.deleteDoc @name, doc._id
          )
        )

TODO only broadcast if the document actually was deleted.

        .then(=>
          broadcast 'documentUpdated', @name, doc._id
        )
        return

      watchServer: ->
        @serverCollection.find().observe
          added:   (doc) => @serverDocChanged doc
          changed: (doc) => @serverDocChanged doc
          removed: (doc) => @serverDocRemoved doc
        return

      updateLocal: (docId, doc) ->
        if doc?
          if doc._id isnt docId
            throw new Error("oops, document id doesn't match")
          if @localCollection.findOne(docId)?
            @localCollection.update(docId, doc)
          else
            @localCollection.insert(doc)
        else
          @localCollection.remove(docId)
        return


      copyServerToLocal: (docId) ->
        @updateLocal docId, @serverCollection.findOne(docId)
        return writeDoc(@name, @localCollection, docId)


      documentUpdated: (docId) ->
        database.transaction(thisApp, 'document updated', =>
          database.readDoc(@name, docId)
        )
        .then((doc) =>
          @updateLocal docId, doc
        )
        return

      loadFromDatabase: ->
        database.mustBeInTransaction()
        idsToDelete = {}
        @localCollection.find({}).forEach((doc) -> idsToDelete[doc._id] = true)
        database.readDocsInCollection(@name)
        .then((docs) =>
          for docId, doc of docs
            delete idsToDelete[doc._id]
            @updateLocal doc._id, doc
          for id in idsToDelete
            @localCollection.remove id
          return
        )

      writeMethodChanges: (methodId) ->
        database.mustBeInTransaction()
        originals = @localCollection.retrieveOriginals()
        writes = []
        for docId of originals
          writes.push writeDoc(@name, @localCollection, docId)
          writes.push database.addDocumentWrittenByStub(methodId, @name, docId)
          broadcast 'documentUpdated', @name, docId
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

    reloadAll = ->
      database.mustBeInTransaction()
      return forEachCollectionResult('loadFromDatabase')

    saveOriginals = ->
      for name, offlineCollection of offlineCollections
        offlineCollection.localCollection.saveOriginals()
      return

    writeDoc = (name, localCollection, docId) ->
      doc = localCollection.findOne(docId)
      if doc?
        return database.writeDoc name, doc
      else
        return database.deleteDoc name, docId

    writeChanges = (methodId) ->
      database.mustBeInTransaction()
      r = forEachCollectionResult('writeMethodChanges', methodId)
      return r

    broadcast.listen 'documentUpdated', (collectionName, id) ->
      return if thisApp.closed
      offlineCollections[collectionName]?.documentUpdated(id)
      return


TODO allow to be called from the server?

    openOfflineCollection = (name) ->
      new OfflineCollection(name).collection


We actually return a Meteor.Collection as our offline collection
(munged internally to use the "offline" connection)... so the API
can't be "new OfflineCollection".  But the API will have to change
anyway to support getting the results of calling methods.

    Offline.openCollection = openOfflineCollection
