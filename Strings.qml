import QtQuick

// The plugin's strings, in the language picked under Setup > Language.
//
// Omarchy 4.5 ships Commons.Translations, which reads i18n/ and follows the
// language live. A shell from before it has no such type, and naming it here
// outright would stop the panel and the service loading there at all, so it
// is created by name when the shell has it. Without it nothing is translated:
// every call carries its English text, and that is what comes back.
QtObject {
  id: root

  property var shared: null

  function t(key, fallback) {
    return shared ? shared.t(key, fallback) : fallback
  }

  function tn(key, count, fallback) {
    return shared ? shared.tn(key, count, fallback) : fallback
  }

  Component.onCompleted: {
    try {
      var translations = Qt.createQmlObject("import qs.Commons\nTranslations {}", root, "before-sunset-strings")
      translations.directory = Qt.resolvedUrl("i18n")
      shared = translations
    } catch (e) {
      shared = null
    }
  }
}
