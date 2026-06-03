import trimesh
import numpy as np
import math
import os

models_dir = r"C:\Users\USER\Desktop\Work\Freelance\arabic_game\models"
out_dir = r"C:\Users\USER\Desktop\Work\Freelance\arabic_game\sprites\animal_previews"
os.makedirs(out_dir, exist_ok=True)

glb_files = []
for root, dirs, files in os.walk(models_dir):
    for f in files:
        if f.endswith('.glb'):
            glb_files.append(os.path.join(root, f))

pending = [p for p in glb_files if not os.path.exists(
    os.path.join(out_dir, os.path.splitext(os.path.basename(p))[0] + ".png"))]
print(f"To render: {len(pending)}")

for i, glb_path in enumerate(pending):
    name = os.path.splitext(os.path.basename(glb_path))[0]
    out_path = os.path.join(out_dir, name + ".png")

    print(f"({i+1}/{len(pending)}) {name}...", end=" ", flush=True)

    try:
        scene = trimesh.load(glb_path, force='scene')
        s = scene.scene() if hasattr(scene, 'scene') else scene

        center = s.centroid
        extents = s.extents
        radius = max(extents) * 1.5

        distance = radius
        azimuth = math.radians(30)
        elevation = math.radians(25)

        eye = np.array([
            center[0] + distance * math.cos(azimuth) * math.cos(elevation),
            center[1] + distance * math.sin(elevation),
            center[2] + distance * math.sin(azimuth) * math.cos(elevation)
        ])
        target = center

        forward = (target - eye) / np.linalg.norm(target - eye)
        world_up = np.array([0, 1, 0])
        right = np.cross(forward, world_up)
        right = right / np.linalg.norm(right)
        up = np.cross(right, forward)

        cam = np.eye(4)
        cam[:3, 0] = right
        cam[:3, 1] = up
        cam[:3, 2] = -forward
        cam[:3, 3] = eye

        s.camera_transform = cam

        png = s.save_image(resolution=(512, 512))
        with open(out_path, "wb") as f:
            f.write(png)
        print("OK")
    except Exception as e:
        print(f"ERROR: {e}")

print(f"\nDone!")
