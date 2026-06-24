# Third-party credits

The cloud raymarching in `cloud_overlay.gdshader` is ported and adapted from
Clay John's open-source volumetric cloud demo, re-worked here into a separate
premultiplied-alpha overlay layer (rendered on a camera-locked sky-dome and
occluded by scene geometry) rather than a Sky material.

## Cloud raymarch shader

- **Source:** clayjohn — `godot-volumetric-cloud-demo` (`clouds.gdshader`)
  https://github.com/clayjohn/godot-volumetric-cloud-demo
- **Author:** Clay John (Godot core rendering contributor)
- **License:** MIT

### Original MIT license

The upstream demo ships the standard Godot Engine MIT license:

```
MIT License

Copyright (c) 2007-2021 Juan Linietsky, Ariel Manzur.
Copyright (c) 2014-2021 Godot Engine contributors.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Techniques / references

The cloud model and its lighting draw on published rendering research:

- Andrew Schneider / Guerrilla — "The Real-time Volumetric Cloudscapes of
  Horizon: Zero Dawn", SIGGRAPH 2015 (Perlin-Worley noise, density-height
  gradients, Beer-Powder lighting).
- Sébastien Hillaire (Epic Games) — "A Scalable and Production Ready Sky and
  Atmosphere Rendering Technique", SIGGRAPH 2020 (multi-octave multiple
  scattering approximation).
- Unreal Engine — Volumetric Cloud Component documentation.
- pixelsnafu — "Useful Resources for Rendering Volumetric Clouds" (link hub).
