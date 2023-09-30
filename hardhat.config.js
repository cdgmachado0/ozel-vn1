require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();


module.exports = {
  solidity: "0.8.21",
  networks: {
    hardhat: {
      forking: {
        url: process.env.ARBITRUM,
        blockNumber: 136177703
      }
    }
  }
};
