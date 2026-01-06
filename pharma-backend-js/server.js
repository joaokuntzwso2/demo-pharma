const { createApp } = require("./src/app");

const PORT = process.env.PORT || 8080;

const app = createApp();

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Pharma backend (BR) listening on port ${PORT}`);
});
