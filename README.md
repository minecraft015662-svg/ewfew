# VPS Migrate GUI

Static web page. Fill 2 destination VPS details, get one command, paste it on the source VPS.

## GitHub par upload
1. github.com par new repo banao (`vps-migrate-gui`).
2. Teeno files (`index.html`, `render.yaml`, `README.md`) upload karo ("Add file > Upload files") ya:
   ```
   git init && git add . && git commit -m "init"
   git branch -M main
   git remote add origin https://github.com/<username>/vps-migrate-gui.git
   git push -u origin main
   ```

## Render par host
1. dashboard.render.com > New > **Static Site**
2. GitHub repo connect karo
3. Build Command: khali chhodo, Publish Directory: `.`
4. Create. Link mil jayega (`https://vps-migrate-gui.onrender.com`).
