import os
import re

for root, dirs, files in os.walk('lib/'):
    for file in files:
        if file.endswith('.dart'):
            with open(os.path.join(root, file), 'r') as f:
                content = f.read()
                # look for dotenv.env['KEY'] and the adjacent url paths
                keys = re.findall(r"dotenv\.env\[['\"](.*?)['\"]\]", content)
                if keys:
                    print(f"\n--- {file} ---")
                    lines = content.split('\n')
                    for i, line in enumerate(lines):
                        if 'env[' in line:
                            # print the line and next 5 lines
                            for j in range(max(0, i-2), min(len(lines), i+8)):
                                if any(x in lines[j] for x in ['http', 'api', 'Uri.parse', 'env[']):
                                    print(lines[j].strip())
