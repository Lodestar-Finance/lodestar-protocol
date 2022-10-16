#!/bin/bash

yarn test tests/Comptroller/accountLiquidityTest.js

yarn test tests/Comptroller/adminTest.js

yarn test tests/Comptroller/assetsListTest.js

yarn test tests/Comptroller/comptrollerTest.js

yarn test tests/Comptroller/liquidateCalculateAmountSeizeTest.js

yarn test tests/Comptroller/pauseGuardianTest.js

yarn test tests/Comptroller/proxiedComptrollerV1Test.js

yarn test tests/Comptroller/unitrollerTest.js

yarn test tests/Lens/CompoundLensTest.js

yarn test tests/Tokens/accrueInterestTest.js

yarn test tests/Tokens/adminTest.js

yarn test tests/Tokens/borrowAndRepayCEtherTest.js

yarn test tests/Tokens/borrowAndRepayTest.js

yarn test tests/Tokens/cTokenTest.js

yarn test tests/Tokens/liquidateTest.js

yarn test tests/Tokens/mintAndRedeemCEtherTest.js

yarn test tests/Tokens/mintAndRedeemTest.js

yarn test tests/Tokens/reservesTest.js

yarn test tests/Tokens/safeTokenTest.js

yarn test tests/Tokens/setComptrollerTest.js

yarn test tests/Tokens/setInterestRateModelTest.js

yarn test tests/Tokens/transferTest.js

yarn test tests/Models/InterestRateModelTest.js

yarn test MaximillionTest.js

yarn test PriceOracleProxyETHTest.js

yarn test SpinaramaTest.js