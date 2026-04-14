import os
import glob
import numpy as np
from PIL import Image, ImageOps 
import imageio

image_dir = 'AlbaManager_UserManual/images'
output_path = 'AlbaManager_UserManual/user_manual_video.mp4'

png_files = sorted(glob.glob(os.path.join(image_dir, '*.png')))
if not png_files:
    print("No PNG files found.")
    exit(1)

print(f"Found {len(png_files)} images. Processing...")

# Define standard size based on the first image or a typical smartphone screen
target_width = 1080
target_height = 2340

writer = imageio.get_writer(output_path, fps=0.5) # 1 frame per 2 seconds

try:
    for file in png_files:
        img = Image.open(file).convert('RGB')
        # Scale and pad to fit target size without stretching
        img_padded = ImageOps.pad(img, (target_width, target_height), color=(242, 242, 247))
        writer.append_data(np.array(img_padded))
except Exception as e:
    print(f"Error processing {file}: {e}")
finally:
    writer.close()
    
print(f"🎉 Video successfully created at: {output_path}")
