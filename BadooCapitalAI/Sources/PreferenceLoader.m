/*
 * Preferences plist for Preferenceloader (Settings.app → BadooCapitalAI)
 * Drop BadooCapitalAI.bundle into /Library/PreferenceBundles/
 * and Root.plist into the bundle.
 *
 * This file documents the structure; actual Root.plist is generated below.
 */

// Root.plist content (write this to BadooCapitalAI.bundle/Root.plist):
/*
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>title</key>
    <string>BadooCapitalAI</string>
    <key>items</key>
    <array>
        <dict>
            <key>cell</key>     <string>PSGroupCell</string>
            <key>label</key>    <string>Main</string>
        </dict>
        <dict>
            <key>cell</key>         <string>PSSwitchCell</string>
            <key>key</key>          <string>enabled</string>
            <key>label</key>        <string>Enable</string>
            <key>default</key>      <false/>
        </dict>
        <dict>
            <key>cell</key>     <string>PSGroupCell</string>
            <key>label</key>    <string>Capital AI</string>
        </dict>
        <dict>
            <key>cell</key>         <string>PSEditTextCell</string>
            <key>key</key>          <string>licenseKey</string>
            <key>label</key>        <string>License Key</string>
            <key>placeholder</key>  <string>YOUR_LICENSE_KEY</string>
        </dict>
        <dict>
            <key>cell</key>         <string>PSEditTextCell</string>
            <key>key</key>          <string>modelId</string>
            <key>label</key>        <string>Model ID</string>
            <key>default</key>      <string>43</string>
            <key>keyboardType</key> <integer>1</integer>
        </dict>
        <dict>
            <key>cell</key>         <string>PSEditTextCell</string>
            <key>key</key>          <string>presetId</string>
            <key>label</key>        <string>Preset ID</string>
            <key>default</key>      <string>88</string>
            <key>keyboardType</key> <integer>1</integer>
        </dict>
    </array>
</dict>
</plist>
*/
