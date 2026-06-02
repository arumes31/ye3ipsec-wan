import os

def fix_line_endings(directory):
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.sh'):
                path = os.path.join(root, file)
                with open(path, 'rb') as f:
                    content = f.read()
                
                # Replace CRLF with LF and remove UTF-8 BOM
                new_content = content.replace(b'\r\n', b'\n')
                if new_content.startswith(b'\xef\xbb\xbf'):
                    new_content = new_content[3:]
                
                if new_content != content:
                    print(f"Fixing {path}")
                    with open(path, 'wb') as f:
                        f.write(new_content)

fix_line_endings('patches')
fix_line_endings('src')
