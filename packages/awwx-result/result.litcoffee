    {Fanout} = awwx
    {catcherr, reportError} = awwx.err


    class Result

      constructor: ->
        @_done = false
        @_failed = null
        @_doneFanout = Fanout()

      on: (callback) ->
        unless typeof callback is 'function'
          throw new Error("Result.on: callback is not a function: #{callback}")
        if @_done
          catcherr => callback(@_failed, @_value, this)
        else
          @_doneFanout.listen(callback)
        this

      callback: (cb) ->
        @on(cb)

      onSuccess: (cb) ->
        unless typeof cb is 'function'
          throw new Error "Result.onSuccess: callback is not a function: #{cb}"
        @callback (failed, value) =>
          return if failed
          catcherr => cb(value, this)
          return
        this

      onFailure: (cb) ->
        unless typeof cb is 'function'
          throw new Error "Result.onFail: callback is not a function: #{cb}"
        @callback (failed, value) =>
          return unless failed
          catcherr => cb(failed, this)
          return
        this

      _broadcast: ->
        @_doneFanout(@_failed, @_value, this)
        @_doneFanout.dispose()
        return

      complete: (value) ->
        return this if @_done
        if value instanceof Result
          @from(value)
          return
        @_done = true
        @_value = value
        @_broadcast()
        return this

      fail: (failure) ->
        return this if @_done
        @_done = true
        @_failed = failure ? true
        @_broadcast()
        return this

      into: (result) ->
        @callback (failed, value) =>
          if failed
            result.fail()
          else
            result.complete(value)
        return this

      from: (result) ->
        result.into(this)
        return this

      _run: (fn, arg) ->
        try
          ret = fn(arg)
        catch error
          reportError error
          @fail()
          return
        if ret instanceof Result
          @from(ret)
        else
          @complete(ret)
        return

      then: (successFn, failureFn) ->
        if successFn? and not typeof successFn is 'function'
          throw new Error "Result.then: successFn is not a function: #{successFn}"
        if failureFn? and not typeof failureFn is 'function'
          throw new Error "Result.then: failureFn is not a function: #{failureFn}"

        result = new Result()

        @callback (failure, value) =>
          if failure?
            if failureFn?
              result._run(failureFn, failure)
            else
              result.fail()
          else
            if successFn?
              result._run(successFn, value)
            else
              result.complete(value)
          return

        return result


TODO more like https://github.com/cujojs/when/blob/2.1.0/when.js#L80

      always: (fn) ->
        f = ->
          fn()
          return
        return @then(f, f)

      @value: (v) ->
        result = new Result()
        result.complete(v)
        return result

      @completed: (v) ->
        return Result.value(v)

      @failed: (failure) ->
        result = new Result()
        result.fail(failure)
        return result


TODO clear timeout if result finishes before the timeout

      @delay: (milliseconds, v) ->
        result = new Result()
        Meteor.setTimeout((-> result.complete(v)), milliseconds)
        return result

      @defer: (v) ->
        result = new Result()
        Meteor.defer(-> result.complete(v))
        return result

      @join: (results) ->
        if results.length is 0
          return Result.completed([])

        finalResult = new Result()
        total = results.length
        nComplete = 0
        output = []
        for result, i in results
          do (result, i) ->
            result.callback (failure, value) ->
              if failure
                finalResult.fail(failure)
              else
                output[i] = value
                ++nComplete
                if nComplete is total
                  finalResult.complete(output)
        return finalResult

      @sequence: (input, fns) ->
        finalResult = new Result()
        i = 0
        next = (value) ->
          result = new Result()
          result._run(fns[i], value)
          result.callback (failure, nextValue) ->
            if failure?
              finalResult.fail(failure)
              return
            ++i
            if i is fns.length
              finalResult.complete(nextValue)
            else
              next(nextValue)
            return
          return
        Result.value(input).callback (failure, nextValue) ->
          if failure?
            finalResult.fail(failure)
            return
          next(nextValue)
          return
        return finalResult

      timeout: (milliseconds) ->
        result = new Result()
        delay = Result.delay(milliseconds)
        delay.onSuccess -> result.fail('timeout')
        this.into(result)
        return result

      done: ->
        result = new Result()
        @callback -> result.complete()
        return result

    (@awwx or= {}).Result = Result
