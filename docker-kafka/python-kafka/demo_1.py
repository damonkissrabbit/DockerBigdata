import os
import shutil

file_path = r"C:\Users\star\Documents\WeChat Files\wxid_kor8xca5ob0x22\FileStorage\File"
dst_dir = r"C:\Users\star\Desktop\economists-pdfs"

for root, dirs, files in os.walk(file_path):
    for file in files:
        if file.endswith(".pdf"):
            shutil.move(os.path.join(root, file), dst_dir + "/" + file)
