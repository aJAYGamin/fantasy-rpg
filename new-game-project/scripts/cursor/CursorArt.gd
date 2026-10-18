class_name CursorArt
extends RefCounted

## The themed cursor's art catalogue: 10 shapes x 20 colours, all pure data.
##
## Source of truth is .claude/docs/superpowers/specs/2026-10-17-themed-cursor-art.html.
## Its shapes are SVG <symbol>s whose paints are CSS custom properties; Godot's SVG
## rasteriser has no CSS variables, so each shape here is a body template whose paints
## are {token} placeholders, and svg() fills them from the colour's palette and returns
## one complete, literal SVG document. Nothing here draws to the screen: texture()
## rasterises that document for the cursor nodes to draw, and image() rasterises it at
## any scale for a one-off use (the system pointer).
##
## Textures are rasterised at RENDER_SCALE (4x) and drawn at a quarter size so the
## cursor stays crisp, and each carries GLOW_MARGIN symbol units of transparent padding
## on every side, which is the room the hover glow needs to spread without being clipped.

const SHAPES: Array[String] = ["A", "B", "K", "L", "S", "AB", "AK", "AR", "AS", "AV"]
const COLOURS: Array[String] = [
	"amethyst", "arcane", "rose", "garnet", "ember", "blaze", "gilded", "storm", "terra", "venom",
	"gale", "grove", "spirit", "frost", "tidal", "abyss", "void", "obsidian", "steel", "lunar",
]
const DEFAULT_SHAPE := "A"
const DEFAULT_COLOUR := "amethyst"

## Textures are rasterised at this multiple of the art's size and drawn at 1/RENDER_SCALE.
const RENDER_SCALE := 4.0
## Transparent padding, in symbol units, around every texture (room for the glow).
const GLOW_MARGIN := 10.0

## The shared dark outline under every shape, as SVG attributes (the art file's
## --edge is rgba(8,5,16,.85)).
const EDGE := 'stroke="#080510" stroke-opacity="0.85"'
## The classic arrow outline that A, K, AS and AV all share.
const ARROW := "M1.5,1.5 L1.5,22 L6.8,16.8 L10.6,25.8 L14,24.3 L10.3,15.4 L17.6,15.4 Z"

## Void, Obsidian and Lunar keep the original cut of AK and AR (lighter centre, thinner
## edge); the other seventeen colours use the deeper one. See AK_* / AR_* below.
const ORIGINAL_CUT: Array[String] = ["void", "obsidian", "lunar"]
## Their dots need a 1 px ring to show against the dark settings panel.
const RING_SWATCHES: Array[String] = ["void", "obsidian"]

## Which shade (an index into a palette's "s") fills each AK / AR slot. AK reads
## akt, ak1..ak4 and AR reads ar0..ar6, in that order.
const AK_DEEP: Array[int] = [2, 3, 4, 5, 6]
const AK_ORIGINAL: Array[int] = [0, 1, 3, 5, 6]
const AR_DEEP: Array[int] = [2, 3, 4, 5, 5, 6, 7]
const AR_ORIGINAL: Array[int] = [0, 1, 2, 3, 4, 5, 6]
## AR's heavier edge for the deeper cut, so it stands off the bright plains.
const AR_EDGE_DEEP := "3.8"
const AR_EDGE_ORIGINAL := "3"

## The hover glow is a light and a mid tone of the colour (s2, s4); the dark and white
## colours glow in their rim colour instead.
const GLOW_OVERRIDES := {
	"void": ["#B48CFF", "#8C59F2"],
	"obsidian": ["#D9D9E6", "#8C8C99"],
	"lunar": ["#FFFFFF", "#B9C0D4"],
}

## Per shape: display name, the art's viewBox, the tip (the click point) in symbol
## units, and the body template.
const SHAPE_DATA := {
	"A": {"name": "Amethyst Arrow", "view": Rect2(-1, -1, 21, 29), "tip": Vector2(1.5, 1.5), "body": BODY_A},
	"B": {"name": "Crystal Shard", "view": Rect2(-1, -1, 25, 25), "tip": Vector2(1.5, 1.5), "body": BODY_B},
	"K": {"name": "Gem-cut Arrow", "view": Rect2(-1, -1, 21, 29), "tip": Vector2(1.5, 1.5), "body": BODY_K},
	"L": {"name": "Dart", "view": Rect2(-1, -1, 25, 25), "tip": Vector2(1.5, 1.5), "body": BODY_L},
	"S": {"name": "Prism", "view": Rect2(-1, -1, 23, 23), "tip": Vector2(1.5, 1.5), "body": BODY_S},
	"AB": {"name": "Sticker Arrow", "view": Rect2(-1, -1, 23, 31), "tip": Vector2(2.5, 2.5), "body": BODY_AB},
	"AK": {"name": "Brilliant Diamond", "view": Rect2(-1, -1, 22, 22), "tip": Vector2(1.5, 1.5), "body": BODY_AK},
	"AR": {"name": "Trilliant", "view": Rect2(-1, -1, 22, 22), "tip": Vector2(1.5, 1.5), "body": BODY_AR},
	"AS": {"name": "Starlit Arrow", "view": Rect2(-1, -1, 21, 29), "tip": Vector2(1.5, 1.5), "body": BODY_AS},
	"AV": {"name": "Low-Poly Arrow", "view": Rect2(-1, -1, 21, 29), "tip": Vector2(1.5, 1.5), "body": BODY_AV},
}

## One palette per colour, from the art file's .c-<colour> rules: the dot colour shown
## in Settings; s0..s7 light to dark; the rim, the flat sticker fill and its border;
## the day gradient (A) and the night gradient (AS) as literal stops.
const PALETTES := {
	"amethyst": {
		"name": "Amethyst", "swatch": "#8C59F2",
		"s": ["#E2D0FF", "#C9A8FF", "#B48CFF", "#9C6BF5", "#7E4FE0", "#6A3BC9", "#4B2A99", "#3A2860"],
		"rim": "#EBDBFF", "flat": "#A87BFF", "border": "#1A1030",
		"day": ["#B48CFF", "#4B2A99"],
		"night": ["#6A3BC9", "#3A2860", "#140C24"],
	},
	"arcane": {
		"name": "Arcane", "swatch": "#C45AE6",
		"s": ["#FBE0FF", "#F2BFFF", "#E394FA", "#D06BF0", "#B84FDB", "#9A36BF", "#6A1F8A", "#48145E"],
		"rim": "#FBE6FF", "flat": "#D06BF0", "border": "#22082D",
		"day": ["#E394FA", "#6A1F8A"],
		"night": ["#9A36BF", "#48145E", "#18061F"],
	},
	"rose": {
		"name": "Rose", "swatch": "#E0559E",
		"s": ["#FFF0F8", "#FFE0F2", "#FFC2E8", "#FF9AD2", "#F078B8", "#E0559E", "#A3295F", "#6E1C40"],
		"rim": "#FFE8F5", "flat": "#FF8FCB", "border": "#2A0A1A",
		"day": ["#FFC2E8", "#A3295F"],
		"night": ["#E0559E", "#6E1C40", "#220816"],
	},
	"garnet": {
		"name": "Garnet", "swatch": "#A8213F",
		"s": ["#FFD6DE", "#F5A3B4", "#E36A84", "#C93A5A", "#A8213F", "#87132E", "#5C0A1E", "#3D0613"],
		"rim": "#FFDCE3", "flat": "#B82C4B", "border": "#1F030A",
		"day": ["#E36A84", "#5C0A1E"],
		"night": ["#87132E", "#3D0613", "#14020A"],
	},
	"ember": {
		"name": "Ember", "swatch": "#F24D4D",
		"s": ["#FFE6E6", "#FFD0D0", "#FFA8A8", "#FF7A7A", "#EB5555", "#D93A3A", "#9E1F1F", "#6E1515"],
		"rim": "#FFE6E6", "flat": "#FF7070", "border": "#2A0B0B",
		"day": ["#FFA8A8", "#9E1F1F"],
		"night": ["#D93A3A", "#6E1515", "#220707"],
	},
	"blaze": {
		"name": "Blaze", "swatch": "#FF8C3A",
		"s": ["#FFF0E3", "#FFD9B8", "#FFBC85", "#FF9A4D", "#F57F26", "#E0650F", "#A84400", "#702E00"],
		"rim": "#FFEFE0", "flat": "#FF8C3A", "border": "#2A1405",
		"day": ["#FFBC85", "#A84400"],
		"night": ["#E0650F", "#702E00", "#241000"],
	},
	"gilded": {
		"name": "Gilded", "swatch": "#D4A12A",
		"s": ["#FFF6D6", "#FFE7A3", "#F9D36B", "#EDB938", "#D49A1C", "#B07A0E", "#74500A", "#4D3506"],
		"rim": "#FFF3CC", "flat": "#EDB938", "border": "#261A03",
		"day": ["#F9D36B", "#74500A"],
		"night": ["#B07A0E", "#4D3506", "#1A1203"],
	},
	"storm": {
		"name": "Storm", "swatch": "#E6B800",
		"s": ["#FFFDE6", "#FFF8C8", "#FFEE8A", "#FFE45C", "#F2CC2A", "#E6B800", "#A37A00", "#6E5300"],
		"rim": "#FFFBE0", "flat": "#FFDF4D", "border": "#2A2000",
		"day": ["#FFEE8A", "#A37A00"],
		"night": ["#E6B800", "#6E5300", "#1F1800"],
	},
	"terra": {
		"name": "Terra", "swatch": "#B9783A",
		"s": ["#FFF4E6", "#F7DDB5", "#EEC48E", "#E0A868", "#CC8F50", "#B9783A", "#7A4A1E", "#55331A"],
		"rim": "#FFF1DC", "flat": "#E6A862", "border": "#241405",
		"day": ["#EEC48E", "#7A4A1E"],
		"night": ["#B9783A", "#55331A", "#1E1005"],
	},
	"venom": {
		"name": "Venom", "swatch": "#B6F23A",
		"s": ["#F6FFDB", "#E6FFA8", "#D2FA6E", "#BDF23A", "#A2DB1F", "#84BF0F", "#557F05", "#385503"],
		"rim": "#F4FFD6", "flat": "#B6F23A", "border": "#172303",
		"day": ["#D2FA6E", "#557F05"],
		"night": ["#84BF0F", "#385503", "#121C02"],
	},
	"gale": {
		"name": "Gale", "swatch": "#8CF273",
		"s": ["#EFFFEA", "#DFFFD6", "#C2F7B0", "#A6F28F", "#80DE6A", "#5FCC48", "#34912A", "#23631C"],
		"rim": "#EFFFEA", "flat": "#8CE870", "border": "#0E240A",
		"day": ["#C2F7B0", "#34912A"],
		"night": ["#5FCC48", "#23631C", "#0A1C08"],
	},
	"grove": {
		"name": "Grove", "swatch": "#22A35E",
		"s": ["#D9FFE8", "#A8F0C6", "#6FDB9E", "#3CC27A", "#22A35E", "#158448", "#0B5C30", "#063D20"],
		"rim": "#DFFFEC", "flat": "#2FB56C", "border": "#031A0D",
		"day": ["#6FDB9E", "#0B5C30"],
		"night": ["#158448", "#063D20", "#021209"],
	},
	"spirit": {
		"name": "Spirit", "swatch": "#3FC9A3",
		"s": ["#ECFFF9", "#D6FFF2", "#B0F8E2", "#8FF2D3", "#66DDBA", "#3FC9A3", "#1F8F75", "#156250"],
		"rim": "#E6FFF8", "flat": "#70E6C4", "border": "#08241D",
		"day": ["#B0F8E2", "#1F8F75"],
		"night": ["#3FC9A3", "#156250", "#061E18"],
	},
	"frost": {
		"name": "Frost", "swatch": "#5CCFEA",
		"s": ["#F7FEFF", "#E0FBFF", "#C2F4FF", "#A8EEFF", "#7FDDF2", "#5CCFEA", "#2A8FB0", "#1E6A82"],
		"rim": "#F0FDFF", "flat": "#8FE6F7", "border": "#0A2028",
		"day": ["#C2F4FF", "#2A8FB0"],
		"night": ["#5CCFEA", "#1E6A82", "#081C24"],
	},
	"tidal": {
		"name": "Tidal", "swatch": "#4DA6FF",
		"s": ["#E3F1FF", "#CDE6FF", "#A6D2FF", "#7DBBFF", "#4DA0F0", "#3C8AE6", "#1F5BB0", "#15406F"],
		"rim": "#E6F2FF", "flat": "#6FB4FF", "border": "#0B1A30",
		"day": ["#A6D2FF", "#1F5BB0"],
		"night": ["#3C8AE6", "#15406F", "#07142A"],
	},
	"abyss": {
		"name": "Abyss", "swatch": "#3747AD",
		"s": ["#C9D3FF", "#9DABF5", "#7184E6", "#4E62CF", "#3747AD", "#26338A", "#172160", "#0E1540"],
		"rim": "#C9D3FF", "flat": "#3A4CC2", "border": "#070A1C",
		"day": ["#7184E6", "#172160"],
		"night": ["#26338A", "#0E1540", "#04061A"],
	},
	"void": {
		"name": "Void", "swatch": "#24183F",
		"s": ["#6B55A0", "#5B4385", "#4A3570", "#3A2860", "#2E2050", "#24183F", "#120D1F", "#0B0814"],
		"rim": "#B48CFF", "flat": "#2E2050", "border": "#B48CFF",
		"day": ["#4A3570", "#120D1F"],
		"night": ["#4A3570", "#24183F", "#0B0814"],
	},
	"obsidian": {
		"name": "Obsidian", "swatch": "#1A1A1F",
		"s": ["#8C8C99", "#6E6E7A", "#55555F", "#3E3E47", "#2E2E36", "#222228", "#141418", "#0A0A0D"],
		"rim": "#D9D9E6", "flat": "#2A2A31", "border": "#D9D9E6",
		"day": ["#55555F", "#0A0A0D"],
		"night": ["#3E3E47", "#1A1A1F", "#050506"],
	},
	"steel": {
		"name": "Steel", "swatch": "#788799",
		"s": ["#E3E8EF", "#C9D2DE", "#AEB9C8", "#93A1B3", "#788799", "#5F6E80", "#3F4A57", "#2B333D"],
		"rim": "#EEF2F7", "flat": "#8D9BAD", "border": "#161B21",
		"day": ["#C9D2DE", "#3F4A57"],
		"night": ["#5F6E80", "#2B333D", "#0E1115"],
	},
	"lunar": {
		"name": "Lunar", "swatch": "#E6E9F2",
		"s": ["#FFFFFF", "#F7F8FC", "#E6E9F2", "#D3D8E6", "#B9C0D4", "#9CA5BF", "#6E7894", "#4D556B"],
		"rim": "#FFFFFF", "flat": "#EEF1F8", "border": "#2B3247",
		"day": ["#FFFFFF", "#9CA5BF"],
		"night": ["#9CA5BF", "#4D556B", "#1A1E2A"],
	},
}

## Body templates, transcribed from the art file's <symbol>s. Paints that were
## CSS variables are {tokens}; see _tokens().
const BODY_A := """<defs><linearGradient id="grad" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{day0}"/><stop offset="1" stop-color="{day1}"/></linearGradient></defs>
<path d="{arrow}" fill="none" {edge} stroke-width="3" stroke-linejoin="round"/>
<path d="{arrow}" fill="url(#grad)" stroke="{rim}" stroke-width="1.4" stroke-linejoin="round"/>
"""

const BODY_B := """<polygon points="1.5,1.5 14,5 21.5,21.5 5,14" fill="none" {edge} stroke-width="3" stroke-linejoin="round"/>
<polygon points="1.5,1.5 14,5 11,11" fill="{s1}"/><polygon points="1.5,1.5 11,11 5,14" fill="{s3}"/>
<polygon points="14,5 21.5,21.5 11,11" fill="{s5}"/><polygon points="5,14 11,11 21.5,21.5" fill="{s6}"/>
<polygon points="1.5,1.5 14,5 21.5,21.5 5,14" fill="none" stroke="{rim}" stroke-width="1.3" stroke-linejoin="round"/>
"""

const BODY_K := """<path d="{arrow}" fill="none" {edge} stroke-width="3" stroke-linejoin="round"/>
<polygon points="1.5,1.5 1.5,22 6.5,13" fill="{s1}"/><polygon points="1.5,1.5 6.5,13 17.6,15.4" fill="{s3}"/>
<polygon points="1.5,22 6.8,16.8 10.3,15.4 6.5,13" fill="{s5}"/><polygon points="6.5,13 10.3,15.4 17.6,15.4" fill="{s4}"/>
<polygon points="6.8,16.8 10.6,25.8 14,24.3 10.3,15.4" fill="{s6}"/>
<path d="{arrow}" fill="none" stroke="{rim}" stroke-width="1.3" stroke-linejoin="round"/>
"""

const BODY_L := """<polygon points="1.5,1.5 21,9 11.5,11.5 9,21" fill="none" {edge} stroke-width="3" stroke-linejoin="round"/>
<polygon points="1.5,1.5 21,9 11.5,11.5" fill="{s1}"/><polygon points="1.5,1.5 11.5,11.5 9,21" fill="{s5}"/>
<polygon points="1.5,1.5 21,9 11.5,11.5 9,21" fill="none" stroke="{rim}" stroke-width="1.3" stroke-linejoin="round"/>
"""

const BODY_S := """<polygon points="1.5,1.5 19,8 8,19" fill="none" {edge} stroke-width="3" stroke-linejoin="round"/>
<polygon points="1.5,1.5 19,8 14.725,8.675 5.1,5.1" fill="{s1}"/>
<polygon points="1.5,1.5 5.1,5.1 8.675,14.725 8,19" fill="{s3}"/>
<polygon points="19,8 8,19 8.675,14.725 14.725,8.675" fill="{s6}"/>
<polygon points="5.1,5.1 14.725,8.675 8.675,14.725" fill="{s4}"/>
<polygon points="1.5,1.5 19,8 8,19" fill="none" stroke="{rim}" stroke-width="1.3" stroke-linejoin="round"/>
"""

const BODY_AB := """<path d="M2.5,2.5 L2.5,23 L7.8,17.8 L11.6,26.8 L15,25.3 L11.3,16.4 L18.6,16.4 Z" fill="none" {edge} stroke-width="5.2" stroke-linejoin="round"/>
<path d="M2.5,2.5 L2.5,23 L7.8,17.8 L11.6,26.8 L15,25.3 L11.3,16.4 L18.6,16.4 Z" fill="none" stroke="{border}" stroke-width="3.6" stroke-linejoin="round"/>
<path d="M2.5,2.5 L2.5,23 L7.8,17.8 L11.6,26.8 L15,25.3 L11.3,16.4 L18.6,16.4 Z" fill="{flat}"/>
<path d="M4.4,7 L4.4,16.5" stroke="{s0}" stroke-width="1.4" stroke-linecap="round"/>
"""

const BODY_AK := """<polygon points="1.5,1.5 13.93,6.57 19,19 6.57,13.93" fill="none" {edge} stroke-width="3" stroke-linejoin="round"/>
<polygon points="1.5,1.5 13.93,6.57 11.91,8.59 6.31,6.31" fill="{ak1}"/>
<polygon points="1.5,1.5 6.31,6.31 8.59,11.91 6.57,13.93" fill="{ak2}"/>
<polygon points="13.93,6.57 19,19 14.19,14.19 11.91,8.59" fill="{ak3}"/>
<polygon points="6.57,13.93 8.59,11.91 14.19,14.19 19,19" fill="{ak4}"/>
<polygon points="6.31,6.31 11.91,8.59 14.19,14.19 8.59,11.91" fill="{akt}"/>
<polygon points="1.5,1.5 13.93,6.57 19,19 6.57,13.93" fill="none" stroke="{rim}" stroke-width="1.3" stroke-linejoin="round"/>
"""

const BODY_AR := """<path d="M1.5,1.5 Q10.69,1.98 19,8 Q15.48,15.48 8,19 Q1.98,10.69 1.5,1.5 Z" fill="none" {edge} stroke-width="{arew}" stroke-linejoin="round"/>
<path d="M1.5,1.5 Q10.69,1.98 19,8 Q15.48,15.48 8,19 Q1.98,10.69 1.5,1.5 Z" fill="{ar3}"/>
<polygon points="1.5,1.5 10.47,3.37 5.1,5.1" fill="{ar1}"/>
<polygon points="1.5,1.5 5.1,5.1 3.37,10.47" fill="{ar2}"/>
<polygon points="10.47,3.37 14.725,8.675 5.1,5.1" fill="{ar2}"/>
<polygon points="10.47,3.37 19,8 14.725,8.675" fill="{ar3}"/>
<polygon points="19,8 14.49,14.49 14.725,8.675" fill="{ar5}"/>
<polygon points="14.49,14.49 8.675,14.725 14.725,8.675" fill="{ar4}"/>
<polygon points="14.49,14.49 8,19 8.675,14.725" fill="{ar6}"/>
<polygon points="8,19 3.37,10.47 8.675,14.725" fill="{ar5}"/>
<polygon points="3.37,10.47 5.1,5.1 8.675,14.725" fill="{ar3}"/>
<polygon points="5.1,5.1 14.725,8.675 8.675,14.725" fill="{ar0}"/>
<path d="M5.1,5.1 L14.725,8.675 L8.675,14.725 Z M1.5,1.5 L5.1,5.1 M19,8 L14.725,8.675 M8,19 L8.675,14.725" fill="none" stroke="#FFFFFF" stroke-width=".3" opacity=".5"/>
<path d="M1.5,1.5 Q10.69,1.98 19,8 Q15.48,15.48 8,19 Q1.98,10.69 1.5,1.5 Z" fill="none" stroke="{rim}" stroke-width="1.3" stroke-linejoin="round"/>
"""

const BODY_AS := """<defs>
<linearGradient id="night" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{night0}"/><stop offset=".55" stop-color="{night1}"/><stop offset="1" stop-color="{night2}"/></linearGradient>
<clipPath id="aclip"><path d="{arrow}"/></clipPath>
</defs>
<path d="{arrow}" fill="none" {edge} stroke-width="3" stroke-linejoin="round"/>
<path d="{arrow}" fill="url(#night)"/>
<g clip-path="url(#aclip)">
<ellipse cx="7" cy="13" rx="9" ry="2.2" transform="rotate(48 7 13)" fill="{s3}" opacity=".35"/>
<g fill="#FFFFFF">
<circle cx="3.2" cy="5.2" r=".5"/><circle cx="6.6" cy="7" r=".3"/><circle cx="3.6" cy="12.6" r=".55"/>
<circle cx="8.6" cy="12.4" r=".35"/><circle cx="12" cy="13.8" r=".3"/><circle cx="4.4" cy="18.2" r=".4"/>
<circle cx="9.3" cy="19.8" r=".3"/><circle cx="11.6" cy="22.8" r=".4"/><circle cx="5.6" cy="10" r=".25"/>
</g>
<path d="M5,9 l.35,.8 .8,.35 -.8,.35 -.35,.8 -.35,-.8 -.8,-.35 .8,-.35z" fill="#FFF3B0"/>
</g>
<path d="{arrow}" fill="none" stroke="{rim}" stroke-width="1.3" stroke-linejoin="round"/>
"""

const BODY_AV := """<path d="{arrow}" fill="none" {edge} stroke-width="3" stroke-linejoin="round"/>
<path d="{arrow}" fill="{s5}"/>
<polygon points="1.5,1.5 6.33,5.67 4,8" fill="{s0}"/>
<polygon points="1.5,1.5 4,8 1.5,10" fill="{s1}"/>
<polygon points="6.33,5.67 8.5,9.5 4,8" fill="{s2}"/>
<polygon points="6.33,5.67 11.48,10.12 8.5,9.5" fill="{s3}"/>
<polygon points="4,8 8.5,9.5 7.5,13.8" fill="{s3}"/>
<polygon points="4,8 7.5,13.8 1.5,10" fill="{s2}"/>
<polygon points="1.5,10 7.5,13.8 3.6,15" fill="{s4}"/>
<polygon points="1.5,10 3.6,15 1.5,16.5" fill="{s3}"/>
<polygon points="8.5,9.5 11.48,10.12 12.5,13" fill="{s4}"/>
<polygon points="11.48,10.12 17.6,15.4 12.5,13" fill="{s5}"/>
<polygon points="12.5,13 17.6,15.4 10.3,15.4" fill="{s6}"/>
<polygon points="8.5,9.5 12.5,13 7.5,13.8" fill="{s4}"/>
<polygon points="7.5,13.8 12.5,13 10.3,15.4" fill="{s5}"/>
<polygon points="7.5,13.8 10.3,15.4 6.8,16.8" fill="{s6}"/>
<polygon points="3.6,15 7.5,13.8 6.8,16.8" fill="{s5}"/>
<polygon points="1.5,16.5 3.6,15 6.8,16.8" fill="{s4}"/>
<polygon points="1.5,16.5 6.8,16.8 1.5,22" fill="{s6}"/>
<polygon points="6.8,16.8 9,19.5 10.3,15.4" fill="{s5}"/>
<polygon points="10.3,15.4 9,19.5 11.4,20.5" fill="{s6}"/>
<polygon points="10.3,15.4 11.4,20.5 14,24.3" fill="{s5}"/>
<polygon points="9,19.5 10.6,25.8 11.4,20.5" fill="{s6}"/>
<polygon points="11.4,20.5 10.6,25.8 14,24.3" fill="{s7}"/>
<polygon points="6.8,16.8 10.6,25.8 9,19.5" fill="{s4}"/>
<path d="{arrow}" fill="none" stroke="{rim}" stroke-width="1.25" stroke-linejoin="round"/>
"""

## The texture texture() rasterised last, and its "shape|colour" key. Only one is kept.
static var _texture: ImageTexture = null
static var _texture_key := ""

static func shape_name(id: String) -> String:
	return SHAPE_DATA.get(id, {}).get("name", "")

static func colour_name(id: String) -> String:
	return PALETTES.get(id, {}).get("name", "")

## True when this is a shape and a colour the catalogue has. svg() and texture()
## refuse anything else, so check this first on an id that came from a save file.
static func is_known(shape: String, colour: String) -> bool:
	return SHAPE_DATA.has(shape) and PALETTES.has(colour)

## The colour's dot in Settings. An unknown colour reads as the default's.
static func swatch(colour: String) -> Color:
	var palette: Dictionary = PALETTES.get(colour, PALETTES[DEFAULT_COLOUR])
	return Color(palette["swatch"])

## True when the colour's dot needs its 1 px light ring (as in the art file).
static func swatch_ring(colour: String) -> bool:
	return RING_SWATCHES.has(colour)

## [light, mid] colours for the hover glow. An unknown colour reads as the default's.
static func glow_colours(colour: String) -> Array[Color]:
	var hexes: Array
	if GLOW_OVERRIDES.has(colour):
		hexes = GLOW_OVERRIDES[colour]
	else:
		var palette: Dictionary = PALETTES.get(colour, PALETTES[DEFAULT_COLOUR])
		hexes = [palette["s"][2], palette["s"][4]]
	var result: Array[Color] = [Color(hexes[0]), Color(hexes[1])]
	return result

## The tip's offset from the texture's top-left, in symbol units: the art's tip, less
## the viewBox origin, plus the glow margin. Multiply by the draw scale for pixels.
static func hotspot(shape: String) -> Vector2:
	if not SHAPE_DATA.has(shape):
		return Vector2.ZERO
	var data: Dictionary = SHAPE_DATA[shape]
	var view: Rect2 = data["view"]
	return data["tip"] - view.position + Vector2(GLOW_MARGIN, GLOW_MARGIN)

## A complete, literal SVG document for this shape in this colour ("" if either is
## unknown). The viewBox is the art's, grown by GLOW_MARGIN on every side, and
## width/height equal its size, so rasterising at scale k gives size x k pixels.
static func svg(shape: String, colour: String) -> String:
	if not is_known(shape, colour):
		return ""
	var data: Dictionary = SHAPE_DATA[shape]
	var view: Rect2 = data["view"]
	var grown := view.grow(GLOW_MARGIN)
	var body: String = String(data["body"]).format(_tokens(colour)).strip_edges()
	return '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="%s %s %s %s">\n%s\n</svg>' % [
			String.num(grown.size.x), String.num(grown.size.y),
			String.num(grown.position.x), String.num(grown.position.y),
			String.num(grown.size.x), String.num(grown.size.y), body]

## The shape rasterised at `scale` (default RENDER_SCALE) as an Image, or null if the ids
## are unknown. Not cached: for a one-off use such as dressing the system pointer.
static func image(shape: String, colour: String, scale := RENDER_SCALE) -> Image:
	if not is_known(shape, colour):
		return null
	var img := Image.new()
	var err := img.load_svg_from_string(svg(shape, colour), scale)
	if err != OK:
		push_error("CursorArt: could not rasterise %s in %s (error %d)" % [shape, colour, err])
		return null
	return img

## The cursor's texture: the shape rasterised at RENDER_SCALE, or null if the ids are
## unknown. Only the style asked for last is cached, so stepping through the Mouse page's
## styles doesn't leave them all in memory; asking again for it gives the same texture,
## which the cursor and its popup copies share.
static func texture(shape: String, colour: String) -> ImageTexture:
	var key := "%s|%s" % [shape, colour]
	if key == _texture_key:
		return _texture
	var img := image(shape, colour)
	if img == null:
		return null
	_texture = ImageTexture.create_from_image(img)
	_texture_key = key
	return _texture

## The shape as a small icon (the Settings Mouse page's Cursor Shape row): the cursor's own
## art at RENDER_SCALE without the glow margin, with mipmaps, so it shrinks cleanly into a
## slot a quarter of its size or less (drawn with a mipmap filter). Null if the ids are
## unknown. Not cached: made when the page shows a style.
static func icon(shape: String, colour: String) -> ImageTexture:
	var img := image(shape, colour)
	if img == null:
		return null
	var view: Rect2 = SHAPE_DATA[shape]["view"]
	var margin := int(GLOW_MARGIN * RENDER_SCALE)
	var art := img.get_region(Rect2i(Vector2i(margin, margin), Vector2i(view.size * RENDER_SCALE)))
	art.generate_mipmaps()
	return ImageTexture.create_from_image(art)

## Every {token} a body template can use, resolved for one colour.
static func _tokens(colour: String) -> Dictionary:
	var palette: Dictionary = PALETTES[colour]
	var shades: Array = palette["s"]
	var original := ORIGINAL_CUT.has(colour)
	var tokens := {
		"arrow": ARROW,
		"edge": EDGE,
		"rim": palette["rim"],
		"flat": palette["flat"],
		"border": palette["border"],
		"day0": palette["day"][0],
		"day1": palette["day"][1],
		"night0": palette["night"][0],
		"night1": palette["night"][1],
		"night2": palette["night"][2],
		"arew": AR_EDGE_ORIGINAL if original else AR_EDGE_DEEP,
	}
	for i in shades.size():
		tokens["s%d" % i] = shades[i]
	var ak: Array[int] = AK_ORIGINAL if original else AK_DEEP
	tokens["akt"] = shades[ak[0]]
	for i in range(1, ak.size()):
		tokens["ak%d" % i] = shades[ak[i]]
	var ar: Array[int] = AR_ORIGINAL if original else AR_DEEP
	for i in ar.size():
		tokens["ar%d" % i] = shades[ar[i]]
	return tokens
