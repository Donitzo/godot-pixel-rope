# Godot Pixel Rope

![Sample](https://github.com/Donitzo/godot-pixel-rope/blob/main/images/example.png)

## Description

This project contains a pixelated Verlet-driven rope addon for Godot. The ropes were created specifically for pixelated retro graphics, as they are drawn pixel by pixel instead of as connected quads.

The addon also includes helper functions and more advanced features such as world collisions, cutting, and pinning control points.

## Demo

The [demo project](https://donitz.itch.io/godot-pixel-rope) is hosted on Itch.io and shows a bunch of different rope-like effects.

## Instructions


The demo project is available in the `src` directory. The only files you need to copy into your own project are in the `pixel_rope` directory.

The demo project shows how to configure the ropes in different ways. The inspector variables are documented, so setup should hopefully be fairly self-explanatory.

![Inspector](https://github.com/Donitzo/godot-pixel-rope/blob/main/images/inspector.png)

After you hook up the ropes to the nodes, you will be able to see the rope connections in the editor.

![Editor](https://github.com/Donitzo/godot-pixel-rope/blob/main/images/editor.png)

You can customize the `pixel_rope.gdshader` shader to add your own effects in the fragment shader.

Extend the `PixelRopeController` class, or edit `simulate_points` in the `PixelRope` class directly, if you want to control the rope yourself.

## Feedback & Bug Reports

If there are additional variations you would find useful, or if you find any bugs or have other feedback, please [open an issue](https://github.com/Donitzo/godot-pixel-rope/issues).
