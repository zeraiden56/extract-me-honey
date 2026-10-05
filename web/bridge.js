// Runs inside the Emscripten loader, before Ruby starts and reads /save.json.
(function () {
  var saveKey = 'extract-me-honey-deluxe:v1';
  var prefix = '__HONEY_SAVE__';
  var demo = new URLSearchParams(window.location.search).has('demo');
  var storageFailed = false;

  // A quoted export stays stable when the release build minifies FS internals.
  Module['honeyReadSave'] = function () {
    return FS.readFile('/save.json', { encoding: 'utf8' });
  };

  function saveStatus(message) {
    document.getElementById('save-status').textContent = message;
  }

  function storageError(error) {
    storageFailed = true;
    saveStatus('Salvamento indisponível. Use “Baixar save” para guardar seu progresso.');
    console.warn('Não foi possível acessar o save neste navegador.', error);
  }

  Module['preRun'] = Module['preRun'] || [];
  Module['preRun'].push(function () {
    if (demo) {
      FS.writeFile('/honey-demo', '1');
      saveStatus('Demonstração · progresso temporário');
      return;
    }
    try {
      var saved = window.localStorage.getItem(saveKey);
      if (saved) FS.writeFile('/save.json', saved);
    } catch (error) {
      storageError(error);
    }
  });

  Module['print'] = function (message) {
    if (!message.startsWith(prefix)) {
      console.log(message);
      return;
    }
    if (demo) return;
    try {
      window.localStorage.setItem(saveKey, message.slice(prefix.length));
      storageFailed = false;
      saveStatus('Progresso salvo neste navegador');
    } catch (error) {
      if (!storageFailed) storageError(error);
    }
  };

  Module['postRun'] = Module['postRun'] || [];
  Module['postRun'].push(function () {
    if (document.documentElement.dataset.failed) return;
    document.getElementById('loading').hidden = true;
    document.getElementById('canvas').focus();
    document.getElementById('download-save').disabled = demo;
  });
})();
