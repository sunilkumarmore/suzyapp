module.exports = {
  root: true,
  env: { node: true, es2022: true },
  parser: '@typescript-eslint/parser',
  plugins: ['@typescript-eslint', 'prettier', 'import'],
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended',
    'plugin:import/recommended',
    'plugin:import/typescript',
    'plugin:prettier/recommended', // turns off conflicting style rules + runs prettier
  ],
  parserOptions: {
    ecmaVersion: 'latest',
    sourceType: 'module',
    // IMPORTANT: do NOT point to tsconfig unless you truly want type-aware lint
    // project: ['./tsconfig.eslint.json'],
    // tsconfigRootDir: __dirname,
  },
  ignorePatterns: ['lib/', 'node_modules/', '.eslintrc.js'],
  rules: {
    // These are the ones that were blocking you earlier:
    'require-jsdoc': 'off',
    '@typescript-eslint/no-explicit-any': 'off',
    // Let Prettier handle formatting
    indent: 'off',
    quotes: 'off',
    'comma-dangle': 'off',
  },

  settings: {
    'import/resolver': {
      typescript: {
        project: './tsconfig.json',
      },
      node: true,
    },
  },
};
