---
inclusion: always
---

# Minimalist Code-Art Philosophy

## Core Principles

When crafting code as art:

- **Pure Expression**: Write code that is both functional and aesthetically intentional
- **Essential Elegance**: Every line should serve a purpose—technical or artistic
- **Visual Clarity**: Structure code to be read as composition, not just instruction
- **Intentional Minimalism**: Remove anything that doesn't contribute to the art

## Aesthetic Guidelines

### Code as Canvas

- **Whitespace is composition**: Use spacing deliberately to create visual rhythm
- **Comments as poetry**: When present, comments should enhance understanding with grace
- **Structure reveals intent**: Organization should guide the eye naturally through the logic
- **Names matter**: Variables and functions should be concise yet evocative

### Simplicity Through Refinement

- **Reduce, don't accumulate**: Favor elegant algorithms over feature bloat
- **Abstract with purpose**: Create functions that isolate beautiful concepts
- **One responsibility per module**: Each piece should do one thing exceptionally
- **Prefer clarity over cleverness**: Unless the cleverness itself is the art

## Implementation Approach

### Building the Piece

- **Start with the essence**: Implement core artistic vision first
- **Iterate toward beauty**: Refactor for elegance, not just functionality  
- **Question every addition**: Does this enhance or distract from the art?
- **Preserve the vision**: Stay true to the original creative intent

### Code Organization

```
// Good: Clear visual hierarchy
const vertices = generateMesh();
const colors = applyPalette(vertices);
const scene = compose(vertices, colors);

// Avoid: Visual noise
const vertices = generateMesh(); const colors = applyPalette(vertices); const scene = compose(vertices, colors);
```

### Naming as Art

- **Evocative variables**: `hue`, `pulse`, `drift` over `var1`, `temp`, `x`
- **Minimal but meaningful**: `noise()` not `generateProceduralNoiseValue()`
- **Consistent vocabulary**: Establish an artistic language and maintain it

## Shader-Specific Artistry

### Visual Structure

- **Section dividers**: Use elegant separators for vertex, fragment, utilities
- **Group related functions**: Place noise, lighting, color together
- **Progressive revelation**: Order functions from high-level to primitives

### Mathematical Beauty

- **Express formulae clearly**: Layout complex calculations for readability
- **Constants with meaning**: `const GOLDEN_RATIO = 1.618` not magic numbers
- **Symmetry in code**: Parallel structures for parallel concepts

## Creative Constraints

### What to Include

✓ Functions that express visual concepts
✓ Structures that organize the artistic logic  
✓ Comments that reveal artistic intent
✓ Parameters that control aesthetic qualities

### What to Avoid

✗ Boilerplate that adds no value
✗ Redundant abstractions
✗ Overly generic utilities
✗ Feature anticipation

## Refinement Process

### Iterative Beauty

1. **Capture the essence**: Get the core working
2. **Eliminate the unnecessary**: Remove anything superfluous  
3. **Refine the structure**: Organize for visual and conceptual clarity
4. **Polish the details**: Perfect spacing, naming, and flow

### Testing the Art

- **Test minimally**: Verify it works, then clean up artifacts
- **No test residue**: Remove all debugging code, logs, test files
- **Leave only the art**: The final piece should be pristine

## Technical Excellence

### Performance as Elegance

- **Efficient algorithms**: Beautiful code should also run beautifully
- **Optimal data structures**: Choose structures that match the artistic intent
- **No premature optimization**: But no careless waste either

### Error Handling with Grace

- **Fail elegantly**: Errors should degrade gracefully, not crash harshly
- **Clear diagnostics**: When something breaks, explain it simply
- **Validate thoughtfully**: Check inputs where it matters, trust where appropriate

## The Final Piece

The goal is code that:
- Functions flawlessly
- Reads like poetry
- Reveals its structure naturally
- Contains nothing unnecessary
- Expresses a clear artistic vision

**Code-art is the discipline of making every character count.**