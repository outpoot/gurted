# Canvas API

Gurted features a 2D canvas API similar to HTML5 Canvas, plus shader support.

## Context

```lua
local canvas = gurt.select('#my-canvas')

local ctx = canvas:withContext('2d')
local shaderCtx = canvas:withContext('shader')
```

## 2D Drawing Context

### Rectangle

```lua
-- Fill a solid rectangle
ctx:fillRect(x, y, width, height, color)
ctx:fillRect(50, 50, 100, 75, '#ff0000') -- Red filled rectangle

-- Draw rectangle outline
ctx:strokeRect(x, y, width, height, color, strokeWidth)
ctx:strokeRect(200, 50, 100, 75, '#00ff00', 3) -- Green outline, 3px thick

-- Clear a rectangular area 
ctx:clearRect(x, y, width, height)
ctx:clearRect(80, 80, 40, 40) -- Clear 40x40 area
```

### Circle

```lua
-- Draw filled or outlined circles
ctx:drawCircle(x, y, radius, color, filled)
ctx:drawCircle(150, 100, 30, '#0000ff', true) -- Filled blue circle
ctx:drawCircle(200, 100, 30, '#ff00ff', false) -- Outlined magenta circle
```

### Text

```lua
ctx:drawText(x, y, text, color)
ctx:drawText(20, 250, 'Hello Canvas!', '#ffffff')
ctx:drawText(20, 280, 'Default Font Only', '#ffff00')

-- Font size can be set with setFont (size only, not family)
ctx:setFont('20px sans-serif')  -- Only size matters
ctx:drawText(20, 300, 'Larger text', '#00ff00')

local metrics = ctx:measureText('Sample Text')
local textWidth = metrics.width
```

### Path-Based Drawing

For complex shapes, use path-based drawing methods:

```lua
ctx:beginPath()

-- Move to starting point without drawing
ctx:moveTo(100, 100)

-- Draw line to point
ctx:lineTo(200, 150)
ctx:lineTo(150, 200)
ctx:lineTo(50, 200)

-- Close the path (connects back to start)
ctx:closePath()

-- Draw the path
ctx:stroke() -- Draw outline
-- or
ctx:fill() -- Fill the shape
```

### Advanced Path Methods

#### Arc and Circle Paths

```lua
-- Draw arc (part of circle)
ctx:arc(x, y, radius, startAngle, endAngle, counterclockwise)

-- Example: Draw a quarter circle
ctx:beginPath()
ctx:arc(200, 200, 50, 0, math.pi/2, false) -- 0 to 90 degrees
ctx:stroke()

-- Full circle path
ctx:beginPath()
ctx:arc(300, 200, 40, 0, 2 * math.pi, false) -- 0 to 360 degrees
ctx:fill()
```

#### Curve Methods

```lua
-- Quadratic curve (one control point)
ctx:quadraticCurveTo(controlX, controlY, endX, endY)

-- Example: Smooth curve
ctx:beginPath()
ctx:moveTo(50, 300)
ctx:quadraticCurveTo(150, 250, 250, 300) -- Control point at (150,250)
ctx:stroke()

-- Bezier curve (two control points)
ctx:bezierCurveTo(cp1x, cp1y, cp2x, cp2y, endX, endY)

-- Example: S-curve
ctx:beginPath()
ctx:moveTo(50, 350)
ctx:bezierCurveTo(100, 300, 200, 400, 250, 350)
ctx:stroke()
```

## Styling and Properties

### Setting Draw Styles

```lua
-- Set stroke (outline) color
ctx:setStrokeStyle('#ff0000') -- Red outline
ctx:setStrokeStyle('rgba(255, 0, 0, 0.5)') -- Semi-transparent red
ctx:setStrokeStyle('red-500') -- Tailwind color names
ctx:setStrokeStyle('blue') -- Named colors

-- Set fill color
ctx:setFillStyle('#00ff00') -- Green fill
ctx:setFillStyle('#33aa88') -- Teal fill
ctx:setFillStyle('slate-800') -- Tailwind colors
ctx:setFillStyle('transparent') -- Named transparent

-- Set line width for strokes
ctx:setLineWidth(5) -- 5 pixel wide lines
ctx:setLineWidth(0.5) -- Thin lines

-- Set font for text (size only, not family)
ctx:setFont('20px sans-serif')  -- Only size matters
ctx:setFont('16px Arial')       -- Font family ignored
ctx:setFont('14px monospace')   -- Uses default font at 14px
```

**Color Support**: Canvas color parsing is identical to CSS styling - supports hex colors (`#ff0000`), RGB/RGBA (`rgba(255,0,0,0.5)`), Tailwind color names (`red-500`, `slate-800`), and basic named colors (`red`, `blue`, `transparent`).

### Using Styles in Drawing

```lua
-- Set up styles first
ctx:setFillStyle('#ff6b6b')
ctx:setStrokeStyle('#4ecdc4')
ctx:setLineWidth(3)

-- Then draw with those styles
ctx:fillRect(50, 50, 100, 100)    -- Uses fill style
ctx:strokeRect(200, 50, 100, 100) -- Uses stroke style and line width

-- Styles persist until changed
ctx:setFillStyle('#45b7d1')
ctx:fillRect(50, 200, 100, 100)   -- Now uses blue fill
```

## Transformations

Canvas transformations allow you to modify the coordinate system for drawing operations.

### Basic Transformations

```lua
ctx:save()
ctx:translate(100, 50)
ctx:rotate(math.pi / 4)
ctx:scale(2.0, 1.5)
ctx:fillRect(0, 0, 50, 50)
ctx:restore()
ctx:fillRect(0, 0, 50, 50)
```

### Transformation Examples

```lua
ctx:save()
ctx:translate(200, 200)
ctx:rotate(math.pi / 6)
ctx:drawText(-25, 0, 'Rotated', 'Arial', '#000000')
ctx:restore()

for i = 1, 5 do
    ctx:save()
    ctx:scale(i * 0.3, i * 0.3)
    ctx:strokeRect(100, 100, 50, 50)
    ctx:restore()
end

for angle = 0, 360, 30 do
    ctx:save()
    ctx:translate(200, 200)
    ctx:rotate(math.rad(angle))
    ctx:fillRect(50, -5, 40, 10)
    ctx:restore()
end
```

## Shader Context

For advanced visual effects, use the shader context:

```lua
local canvas = gurt.select('#shader-canvas')
local shaderCtx = canvas:withContext('shader')

shaderCtx:source([[
    shader_type canvas_item;
        
    void fragment() {
        vec2 uv = UV;
        
        // Create animated rainbow effect
        vec3 color = vec3(
            0.5 + 0.5 * cos(TIME + uv.x * 6.0),
            0.5 + 0.5 * cos(TIME + uv.y * 6.0 + 2.0),
            0.5 + 0.5 * cos(TIME + (uv.x + uv.y) * 6.0 + 4.0)
        );
        
        COLOR = vec4(color, 1.0);
    }
]])
```
