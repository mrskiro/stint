icon:
	mkdir -p AppIcon.iconset
	for size in 16 32 128 256 512; do \
		rsvg-convert -w $$size -h $$size logo.svg -o AppIcon.iconset/icon_$${size}x$${size}.png; \
		double=$$((size * 2)); \
		rsvg-convert -w $$double -h $$double logo.svg -o AppIcon.iconset/icon_$${size}x$${size}@2x.png; \
	done
	iconutil -c icns AppIcon.iconset -o AppIcon.icns
	rm -rf AppIcon.iconset
