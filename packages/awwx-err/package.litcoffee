    Package.describe
      summary: "Centralized error reporting"

    Package.on_use (api) ->
      api.add_files('err.js', ['client', 'server'])
