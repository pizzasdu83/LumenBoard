# Changelog

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

## 1.1.0
- New: pick your own icon for any app right in LumenBoard (photo button at the top left). Choose the app, then an image from Photos (with crop) or Files. No Filza needed
- Custom icons win over every theme and can be changed or removed at any time

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
