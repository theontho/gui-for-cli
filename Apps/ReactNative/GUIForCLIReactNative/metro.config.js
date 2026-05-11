const {getDefaultConfig, mergeConfig} = require('@react-native/metro-config');

const path = require('node:path');

const repoRoot = path.resolve(__dirname, '..', '..', '..');

//

/**
 * Metro configuration
 * https://facebook.github.io/metro/docs/configuration
 *
 * @type {import('metro-config').MetroConfig}
 */

const config = {
  watchFolders: [repoRoot],
  //
  resolver: {
    blockList: [
      // This stops "npx @react-native-community/cli run-windows" from causing the metro server to crash if its already running
      new RegExp(
        `${path.resolve(__dirname, 'windows').replace(/[/\\]/g, '/')}.*`,
      ),
      new RegExp(`${path.resolve(__dirname, 'macos').replace(/[/\\]/g, '/')}.*`),
      /.*\.ProjectImports\.zip/,
    ],
    nodeModulesPaths: [path.resolve(__dirname, 'node_modules')],
    //
  },
  transformer: {
    getTransformOptions: async () => ({
      transform: {
        experimentalImportSupport: false,
        inlineRequires: true,
      },
    }),
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
