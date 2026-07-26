const { assert } = require('chai') || require('assert');

contract('StakeV2', accounts => {
  it('should freeze balance for energy', async () => {
    const result = await tronWeb.transactionBuilder.freezeBalanceV2(
      100_000_000,
      'ENERGY',
      accounts[0]
    );

    const signedTx = await tronWeb.trx.sign(result);
    const receipt = await tronWeb.trx.sendRawTransaction(signedTx);

    assert.isTrue(receipt.result, 'freezeBalanceV2 transaction should succeed');
  });
});