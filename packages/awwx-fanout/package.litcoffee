    Package.describe
      summary: "Simply call listening callbacks"

    Package.on_use (api) ->
      api.use('awwx-err')
      api.add_files('fanout.litcoffee', ['client', 'server'])

    Package.on_test (api) ->
      api.use('awwx-fanout')
      api.add_files('fanout-tests.litcoffee', ['client', 'server'])
