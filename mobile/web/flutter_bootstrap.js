{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {canvasKitBaseUrl: 'canvaskit/'},
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      const appRunner = await engineInitializer.initializeEngine();
      await appRunner.runApp();
      clearTimeout(window.viaxLoadTimer);
      document.getElementById('boot')?.remove();
    } catch (error) {
      window.viaxLoadFailed();
    }
  }
}).catch(window.viaxLoadFailed);
