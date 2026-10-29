// Firefox the operator's way: the choices the profile held on 18 Oct (cell 82938), kept here so a new profile or a
// reinstall starts with them. theme.sh firefox-prefs on puts them in the default profile's user.js, in a marked
// block; Firefox sets them again at each start, so a change made in Settings lasts until the next start unless it is
// made here too. Left out: Firefox's own bookkeeping (counters, timestamps, migrations), ids, the window and panel
// sizes, the search region; the theme's prefs are theme.sh firefox's; telemetry, studies, Pocket and sponsored
// content are the system policy's (settings.sh firefox-quiet).

// Start and new tab: the last session back; no top sites, no logo, no sponsored checkboxes
user_pref("browser.startup.page", 3);
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("browser.newtabpage.activity-stream.hideLogo", true);
user_pref("browser.newtabpage.activity-stream.showSponsoredCheckboxes", false);

// Search and address bar: no suggestions, no search terms kept in the bar
user_pref("browser.search.suggest.enabled", false);
user_pref("browser.urlbar.suggest.searches", false);
user_pref("browser.urlbar.showSearchTerms.enabled", false);

// Tabs, toolbars and sidebar
user_pref("browser.tabs.groups.smart.userEnabled", false);
user_pref("browser.toolbars.bookmarks.visibility", "never");
user_pref("browser.theme.toolbar-theme", 0);
user_pref("browser.warnOnQuitShortcut", false);
user_pref("browser.aboutConfig.showWarning", false);
user_pref("sidebar.visibility", "hide-on-close");
user_pref("sidebar.main.tools", "aichat,history,bookmarks,opentabs");
user_pref("privacy.userContext.enabled", false);

// The middle button: no paste, no new tab or window from it, no scroll-bar jump (as KDE is set)
user_pref("middlemouse.paste", false);
user_pref("middlemouse.openNewWindow", false);
user_pref("middlemouse.scrollbarPosition", false);
user_pref("browser.tabs.opentabfor.middleclick", false);
user_pref("browser.tabs.searchclipboardfor.middleclick", false);
user_pref("widget.gtk.middle-click-enabled", false);

// AI features off
user_pref("browser.ai.control.pdfjsAltText", "blocked");
user_pref("browser.ai.control.speechRecognition", "blocked");
user_pref("browser.ml.linkPreview.enabled", false);
user_pref("pdfjs.enableAltText", false);

// Passwords and forms: KeePassXC keeps the passwords
user_pref("signon.rememberSignons", false);
user_pref("signon.management.page.breach-alerts.enabled", false);
user_pref("signon.firefoxRelay.feature", "disabled");
user_pref("extensions.formautofill.creditCards.enabled", false);
user_pref("dom.forms.autocomplete.formautofill", true);
user_pref("privacy.clearOnShutdown_v2.formdata", true);

// Privacy
user_pref("privacy.globalprivacycontrol.enabled", true);
user_pref("nimbus.rollouts.enabled", false);

// Media, translations, spelling
user_pref("media.videocontrols.picture-in-picture.video-toggle.enabled", false);
user_pref("browser.translations.automaticallyPopup", false);
user_pref("layout.spellcheckDefault", 0);
