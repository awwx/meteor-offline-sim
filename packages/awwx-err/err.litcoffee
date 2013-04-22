Uncaught errors come here.

    reportError = (error) ->
      if error?.stack?
        Meteor._debug error.stack
      else if error?.message?
        Meteor._debug error.message
      else
        Meteor._debug error


Report an uncaught exception thrown by `fn`.

    catcherr = (fn, onFailed) ->
      try
        return fn()
      catch error
        reportError error
        onFailed?()
        return

    (@awwx or= {}).err = {reportError, catcherr}
