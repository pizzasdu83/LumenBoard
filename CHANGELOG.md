# Changelog

## 1.7.0
- "How does this work?" now shows images, tables and HTML too: the Markdown file is shown in a web view (JavaScript off). Images of the app (![](help/step1.png) or <img src="help/step1.png">) and https images work
- Tables, nested and task lists, ~~strikethrough~~, quotes, code blocks, links to a part of the page, and HTML such as <details> and <img width=...>

## 1.6.1
- "How does this work?" now shows a Markdown file of the app (App/Resources/HowItWorks.md, German in de.lproj/HowItWorks.md) instead of a text in the code

## 1.6.0
- LumenBoard is now called Slippery Board (the name you see: app, package, texts). Settings, files and the package id stay the same, so nothing is lost
- The icon shape is "iOS shape" by default (a new config; yours stays as you set it)
- A link "How does this work?" at the bottom of the main page opens a short explanation of the screens and settings

## 1.5.4
- The icon background now also goes into the marked icons when the icon shape is a custom one (circle, rounded square, square, teardrop, theme mask), not only with the iOS shape. It is cut by the shape
- The previews of the Custom icons screen show the icon shape of the settings

## 1.5.3
- The icon shape of the settings is for the apps your themes have no icon for and for the icons and themes marked "iOS shape" (swipe right). The other theme icons keep their own shape
- The icon background goes behind the marked icons when the icon shape is "iOS shape"

## 1.5.2
- The previews in the Custom icons screen show the icon background when the preview button at the top is on (together with the iOS shape)

## 1.5.0
- Merged with the original LumenBoard 1.1.0: icon shapes (circle, rounded square, square, teardrop, theme mask), icon effects (Anemone underlays and overlays), Simplified Chinese, the fix for the crash with "On/Off Labels"
- The iOS shape for single icons and themes (swipe right) counts when the icon shape in Settings is "Theme's own shape"
- The icon background only goes behind icons that have the iOS shape (every icon with the shape "iOS shape", or the ones marked for it)
- Themes imported from a zip or a .deb bring their effects (AnemoneEffects) and icon mask along
- Removed for good: "Clear icon cache & respring" ("Rebuild icons" does the job)

## 1.4.1
- The icon background only goes behind icons that have the iOS shape
- Fixed: the color pickers of the icon background were drawn at the wrong place

## 1.4.0
- New: an icon background in Settings. Light and dark mode each have their own: none, a color, a gradient (with an angle) or an image. It goes behind the theme icons and shows where they are transparent

## 1.3.0
- New: import icon themes from a .deb (the import button now takes zips and .deb files). A .deb can hold several themes, only the ones with an IconBundles or Icons folder are imported. Needs dpkg

## 1.2.0
- New: import themes from a zip (button at the top right of the themes list). Imported themes can be deleted with a swipe to the left
- New: the iOS icon shape (squircle) for single icons and single themes. Swipe right on an icon (Custom icons screen, section "iOS shape") or on an active theme, even when "iOS icon shape" is off in Settings
- New: a button at the top of the Custom icons screen previews every icon with the iOS shape
- Removed: "Clear icon cache & respring", "Rebuild icons" does the job
- Imported themes are found next to the themes of the package manager

## 1.1.4
- "Rebuild icons" can now really delete the icon cache: the folder belongs to a system user, so a small root LaunchDaemon (LumenBoardHelper, like the one of Filza) deletes what is inside it

## 1.1.2
- "Rebuild icons" now deletes the icon cache from the app itself (SpringBoard may not be allowed to), shows how many items were deleted and lists the result in Diagnostics

## 1.1.1
- New: "Rebuild icons" in Settings deletes the icon cache of iOS and respring

## 1.0.4
- New: pick your own icon for any app right in LumenBoard (photo button at the top left). Choose the app, then an image from Photos (with crop) or Files. No Filza needed
- Custom icons win over every theme and can be changed or removed at any time

## Original 1.1.0
- Icon shapes: circle, rounded square, square, teardrop, or the icon mask of your theme. They change every app icon, also apps your themes have no icon for (Settings → Icon shape)
- Icon effects: underlays and overlays from themes that have them (Anemone effects in `AnemoneEffects`), drawn into every app icon
- Fixed the app crashing when opening the settings with "On/Off Labels" turned on in the accessibility settings (#4)
- App in Simplified Chinese, thanks to @xiangfeidexiaohuo (#2)
- New shapes and effects show up after tapping Apply

## 1.0.3
- Fixed themes randomly showing "0 icons" and no preview, for example while your package manager is still installing themes
- Themes that change while LumenBoard is open (installed, updated, removed) are picked up right away
- Pull down on the theme list to read every theme again
- A theme that can't be read now says so instead of showing "0 icons"
- Diagnostics list every installed theme, with details for themes that have no icons

## 1.0.2
- Fixed theme previews and icon counts not showing when many themes are installed
- Theme previews load faster and use less memory
- Previews are kept until a theme changes, so they no longer reload every time you open the app

## 1.0.1
- If iconservicesagent renders a theme icon without the theme, SpringBoard now renders it itself (should fix icons not changing on some palera1n devices)
- Large theme icons are scaled down to 512 px to save memory
- New diagnostics page (Settings → Diagnostics) with a report you can copy

## 1.0.0
- First release as LumenBoard
