package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	opentui "github.com/sst/opentui/packages/go"
)

type snapshot struct {
	Version string         `json:"version"`
	Width   uint32         `json:"width"`
	Height  uint32         `json:"height"`
	Cells   []snapshotCell `json:"cells"`
}

type snapshotCell struct {
	Ch string     `json:"ch"`
	Fg [4]float32 `json:"fg"`
	Bg [4]float32 `json:"bg"`
}

func main() {
	scene := flag.String("scene", "S1", "scene id")
	width := flag.Uint("width", 20, "snapshot width")
	height := flag.Uint("height", 5, "snapshot height")
	flag.Parse()

	renderer := opentui.NewRenderer(uint32(*width), uint32(*height))
	if renderer == nil {
		fatalf("failed to create renderer")
	}
	defer func() {
		_ = renderer.Close()
	}()

	buffer, err := renderer.GetNextBuffer()
	must(err)
	must(buffer.Clear(opentui.Transparent))

	switch *scene {
	case "S1":
		must(buffer.DrawText("Hello", 0, 0, opentui.White, nil, 0))
	case "S2":
		drawManualBox(buffer)
	case "S3":
		must(buffer.FillRect(0, 0, 12, 5, opentui.NewRGBA(0.05, 0.05, 0.08, 1)))
		must(buffer.DrawText("Inner", 1, 1, opentui.White, nil, 0))
	case "W1":
		must(buffer.Clear(opentui.NewRGBA(0, 0, 0, 1)))
		must(buffer.DrawText("Hello", 0, 0, opentui.White, nil, 0))
	case "W2":
		must(buffer.Clear(opentui.NewRGBA(0, 0, 0, 1)))
		must(buffer.DrawText("Left", 0, 2, opentui.White, nil, 0))
		must(buffer.DrawText("Middle", 4, 2, opentui.White, nil, 0))
		must(buffer.DrawText("Right", 10, 2, opentui.White, nil, 0))
	case "W3":
		must(buffer.Clear(opentui.NewRGBA(0, 0, 0, 1)))
		must(buffer.DrawText("Line 1", 7, 0, opentui.White, nil, 0))
		must(buffer.DrawText("Line 2", 7, 1, opentui.White, nil, 0))
		must(buffer.DrawText("Line 3", 7, 2, opentui.White, nil, 0))
	default:
		fatalf("unknown scene: %s", *scene)
	}

	direct, err := buffer.GetDirectAccess()
	must(err)

	out := snapshot{
		Version: "1",
		Width:   direct.Width,
		Height:  direct.Height,
		Cells:   make([]snapshotCell, 0, len(direct.Chars)),
	}

	for y := uint32(0); y < direct.Height; y++ {
		for x := uint32(0); x < direct.Width; x++ {
			cell, err := direct.GetCell(x, y)
			must(err)
			out.Cells = append(out.Cells, snapshotCell{
				Ch: string(cell.Char),
				Fg: rgbaArray(cell.Foreground),
				Bg: rgbaArray(cell.Background),
			})
		}
	}

	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	must(encoder.Encode(out))
}

func rgbaArray(color opentui.RGBA) [4]float32 {
	return [4]float32{color.R, color.G, color.B, color.A}
}

func drawManualBox(buffer *opentui.Buffer) {
	background := opentui.NewRGBA(0.1, 0.1, 0.15, 1)

	must(buffer.FillRect(0, 0, 20, 5, background))

	for x := uint32(1); x < 19; x++ {
		must(buffer.SetCellWithAlphaBlending(x, 0, '─', opentui.Cyan, background, 0))
		must(buffer.SetCellWithAlphaBlending(x, 4, '─', opentui.Cyan, background, 0))
	}

	for y := uint32(1); y < 4; y++ {
		must(buffer.SetCellWithAlphaBlending(0, y, '│', opentui.Cyan, background, 0))
		must(buffer.SetCellWithAlphaBlending(19, y, '│', opentui.Cyan, background, 0))
	}

	must(buffer.SetCellWithAlphaBlending(0, 0, '┌', opentui.Cyan, background, 0))
	must(buffer.SetCellWithAlphaBlending(19, 0, '┐', opentui.Cyan, background, 0))
	must(buffer.SetCellWithAlphaBlending(0, 4, '└', opentui.Cyan, background, 0))
	must(buffer.SetCellWithAlphaBlending(19, 4, '┘', opentui.Cyan, background, 0))
}

func must(err error) {
	if err != nil {
		fatalf("%v", err)
	}
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
