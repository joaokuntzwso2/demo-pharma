FROM node:20-alpine

WORKDIR /usr/src/app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY server.js ./
COPY src ./src

EXPOSE 8080
CMD ["npm", "start"]
