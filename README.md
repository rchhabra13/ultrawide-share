# Ultrawide Share

You have two monitors. Teams only lets you share one. So you end up dragging windows back and forth while everyone waits.

Ultrawide Share sits in your Mac's menu bar. Flip it on, and both monitors show up side by side in one window. Share that window, and everyone sees your whole desk as one wide screen. Two 1080p monitors become one 3840×1080 picture.

It works in any app that can share a window: Teams, Zoom, Google Meet, Slack, Webex and the rest.

## Install

You need a Mac with Apple Silicon, macOS 14 or later, and the Xcode command line tools.

```bash
git clone https://github.com/rchhabra13/ultrawide-share.git
cd ultrawide-share
./build.sh
open UltrawideShare.app
```

A two rectangle icon appears in your menu bar.

## Use it

1. Click the menu bar icon and choose **Turn On Ultrawide Share**.
2. The first time, macOS asks for Screen Recording permission. Allow UltrawideShare in System Settings > Privacy & Security > Screen & System Audio Recording, then quit the app from its menu and open it again.
3. A window called **Ultrawide Share** opens with your monitors side by side, arranged the same way they are in your Display settings.
4. In your meeting, share **that window**, not a screen.
5. When you're done, click **Turn Off** or just close the window. Nothing is captured while it's off.

You can pick which displays to combine from the menu while sharing is off. All displays are on by default, except an iPad used as a Sidecar display.

## Good to know

The app leaves its own window out of the capture, so you never get the endless mirror effect. That also means you can hide the window behind other windows and the share keeps going. Minimizing it will stop the share in most meeting apps, so don't do that.

Viewers get the window at the size it has on your screen. A full width window on a 1080p monitor shows the 3840 pixel wide picture at half resolution, so small text can look soft. If you have a Retina screen or an iPad as a Sidecar display, put the window there for a sharper share.

Each rebuild gives the app a new signature, and macOS may ask for Screen Recording permission again. If turning it on fails after a rebuild, remove the old UltrawideShare entry from the Screen Recording list and allow the new one.

Using Zoom only? Zoom can already share two screens at once. Click Share Screen, hold Shift, and pick both desktops. Viewers see two separate screens rather than one wide one, but there's nothing to install.

## How it works

The whole app is one Swift file, [UltrawideShare.swift](UltrawideShare.swift). It uses Apple's ScreenCaptureKit to capture each selected display at full resolution and 30 frames per second, and draws each one into its own layer in a single window. Where each layer goes comes from the display positions macOS reports, so the picture matches your real desk layout. [build.sh](build.sh) compiles it with `swiftc`, wraps it in an app bundle, and signs it so macOS can remember the permission.

## License

MIT. See [LICENSE](LICENSE).
