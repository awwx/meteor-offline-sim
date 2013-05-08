# Broadcast #

Simulated cross browser tab messaging.

A message broadcast is sent to all browser windows, including the
current one.  (In real life it could be implemented using
[browser-msg](https://github.com/awwx/meteor-browser-msg#readme), plus
also sending the message to the current window).


## Client Sim ##

    return unless Meteor.isClient

    if isSim

      Fanout = awwx.Fanout

      Sim.broadcast = {}


Mapping of `messageName` -> `Fanout`; the listeners of this message
topic.

      Sim.broadcast.fanouts = {}

      Sim.broadcast.fanout = (messageName) ->
        Sim.broadcast.fanouts[messageName] or= new Fanout()

      Sim.broadcast.broadcast = (messageTopic, args) ->
        args = EJSON.stringify(args)
        Sim.broadcast.fanout(messageTopic)(args)
        return


## Client App ##

    if isApp

      @broadcast = (messageTopic, args...) ->
        Meteor.defer -> Sim.broadcast.broadcast messageTopic, args
        return

      @broadcast.listen = (messageTopic, callback) ->
        Sim.broadcast.fanout(messageTopic).listen (args) ->
          args = EJSON.parse(args)
          callback(args...)
          return
        return
