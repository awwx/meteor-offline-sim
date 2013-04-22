Result = awwx.Result

Tinytest.addAsync 'result - complete', (test, onComplete) ->
  new Result().complete(3).callback (failed, value) ->
    test.isFalse failed
    test.equal value, 3
    onComplete()

Tinytest.addAsync 'result - join', (test, onComplete) ->
  r1 = Result.delay 10, 'one'
  r2 = Result.delay 20, 'two'
  r3 = Result.delay 30, 'three'
  Result.join([r1, r2, r3]).callback (failure, value) ->
    test.isFalse failure
    test.equal value, ['one', 'two', 'three']
    onComplete()

Tinytest.addAsync 'result - sequence', (test, onComplete) ->
  add3 = (x) -> Result.value(x + 3)
  add5 = (x) -> Result.value(x + 5)
  add7 = (x) -> Result.value(x + 7)
  Result.sequence(0, [add3, add5, add7]).callback (failure, value) ->
    test.isFalse failure
    test.equal value, 15
    onComplete()
