You are an independent art critic for a cozy stylised 3D game. The render is meant to match Alex's supplied reference render: same shapes, proportions, colours, surface finish and charm, as a game-ready model. Judge likeness to the reference, not photorealism. You did not make the render and have no stake in it.

Use `image/file reading tools` to open and inspect every image listed below. Then compare each numbered render crop with the reference photos, which are the supplied design render of the same prop.

Render crops. In each crop image the left half is the render at the judged exposure. When there is a right half, it is the same crop brightened for inspection only.
1. T01 trunk (top camera). Brief: "flared trunk and roots (ref07)". File: /Users/alexdamore/Desktop/Vibe_Code/knitting-empire/art/world_assets/tree/rounds/r01/renders/check_v1/crops/T01.jpg
2. T02 lower_canopy (top camera). Brief: "the wide lower tier of leaf clumps (ref07)". File: /Users/alexdamore/Desktop/Vibe_Code/knitting-empire/art/world_assets/tree/rounds/r01/renders/check_v1/crops/T02.jpg
3. T03 upper_canopy (top camera). Brief: "the upper tiers and crown (ref07)". File: /Users/alexdamore/Desktop/Vibe_Code/knitting-empire/art/world_assets/tree/rounds/r01/renders/check_v1/crops/T03.jpg

Reference photos:
- /Users/alexdamore/Desktop/Vibe_Code/knitting-empire/art/world_assets/tree/ref/ref01_supplied_design.png

For each crop, list up to 3 differences between the render and how the same kind of object looks in the photos, worst first. Judge shape and proportion; how parts sit, hang and rest on each other; edge rounding and wall thickness; surface and material response; wear and dirt; scale. Judge brightness from the left half only. Use the brightened half to see shape and detail.

The reference is a supplied design render of the intended look (soft, rounded, warm, slightly glossy, hand-sculpted). The sky and ground in the render are the test harness, not part of the design.

Judge only the asset. Ignore the sky, the ground and any missing white backdrop or shadow; the reference's white studio background is not part of the asset.

Severity: 3 = gives the render away at the full judged frame; 2 = noticeable on a close look at the judged frame; 1 = only visible in the enlarged crop. If a crop already matches the photos, give no items for it.

Answer with a JSON array only, no other text (use `[]` if every crop matches):
[{"zone": "T01", "severity": 3, "difference": "...", "photo_shows": "... (refNN)", "render_shows": "..."}]
