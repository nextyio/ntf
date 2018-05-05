import assertRevert from '../../helpers/assertRevert';
import expectThrow from '../../helpers/expectThrow';
import expectEvent from '../../helpers/expectEvent';

const NTFToken = artifacts.require('NTFToken');

require('chai')
  .use(require('chai-as-promised'))
  .should();

contract('NTFToken', function (accounts) {
    const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
    const ZERO_TX = '0x0000000000000000000000000000000000000000000000000000000000000000';

    let token;

    const [
        owner,
        recipient,
        blacklistedAddress1,
        blacklistedAddress2,
        anyone,
    ] = accounts;

    const blacklistedAddresses = [blacklistedAddress1, blacklistedAddress2];

    beforeEach(async function () {
        token = await NTFToken.new({from: owner});
    });

    describe('ownership', function () {
        it('should have an owner', async function () {
            let owner_ = await token.owner();
            assert.isTrue(owner_ !== 0);
        });
        
        it('changes owner after transfer', async function () {
            await token.transferOwnership(anyone);
            let owner_ = await token.owner();
        
            assert.isTrue(owner_ === anyone);
        });
        
        it('should prevent non-owners from transfering', async function () {
            const owner_ = await token.owner.call();
            assert.isTrue(owner_ !== recipient);
            await assertRevert(token.transferOwnership(recipient, { from: anyone }));
        });
        
          it('should guard ownership against stuck state', async function () {
            let originalOwner = await token.owner();
            await assertRevert(token.transferOwnership(null, { from: originalOwner }));
          });        
    });
  
    describe('total supply', function () {
        it('returns the total amount of tokens', async function () {
            const totalSupply = await token.totalSupply();
            assert.equal(totalSupply, 10000000 * (10 ** 18));
        });
    });

    describe('transfer', function () {
        describe('when the recipient is not the zero address', function () {
            const to = recipient;
            
            describe('when the sender does not have enough balance', function () {
                const amount = 10000001 * (10 ** 18);
                
                it('reverts', async function () {
                    await assertRevert(token.transfer(to, amount, { from: owner }));
                });
            });
        });

        describe('when the recipient is the zero address', function () {
            const to = ZERO_ADDRESS;
      
            it('reverts', async function () {
                await assertRevert(token.transfer(to, 100, { from: owner }));
            });
        });

        describe('when the sender has enough balance', function () {
            const to = recipient;
            const amount = 100;
    
            it('transfers the requested amount', async function () {
                await expectEvent.inTransaction(
                    token.transfer(to, amount, { from: owner }),
                    'Transfer'
                );
                const senderBalance = await token.balanceOf(owner);
                assert.equal(senderBalance, 10000000 * (10 ** 18));

                const recipientBalance = await token.balanceOf(to);
                assert.equal(recipientBalance, 0);

                let pendingTransfers = await token.getPendingTransfers({ from: owner});
                let pendingReceives = await token.getPendingReceives({ from: to});
                assert.equal(pendingTransfers.length, 1);
                assert.equal(pendingReceives.length, 1);

                await token.transfer(to, amount + 100, { from: owner });
                pendingTransfers = await token.getPendingTransfers({ from: owner});
                pendingReceives = await token.getPendingReceives({ from: to});
                assert.equal(pendingTransfers.length, 2);
                assert.equal(pendingReceives.length, 2);

                await expectEvent.inTransaction(
                    token.confirmTransfer(pendingReceives[0], {from: to}),
                    'TransferConfirmed'
                );
                const fromBalance = await token.balanceOf(owner);
                assert.equal(fromBalance, 10000000 * (10 ** 18) - amount);

                const toBalance = await token.balanceOf(to);
                assert.equal(toBalance, amount);

                pendingTransfers = await token.getPendingTransfers({ from: owner});
                pendingReceives = await token.getPendingReceives({ from: to});
                assert.equal(pendingTransfers.length, 2);
                assert.equal(pendingReceives.length, 2);                
                assert.equal(pendingTransfers[0], ZERO_TX);
                assert.equal(pendingReceives[0], ZERO_TX);
                await expectThrow(
                    token.confirmTransfer(pendingReceives[0], {from: to})
                );

                await expectEvent.inTransaction(
                    token.cancelTransfer(pendingTransfers[1], {from: owner}),
                    'TransferCancelled'
                );
                pendingTransfers = await token.getPendingTransfers({ from: owner});
                pendingReceives = await token.getPendingReceives({ from: to});
                assert.equal(pendingTransfers.length, 2);
                assert.equal(pendingReceives.length, 2);
                assert.equal(pendingTransfers[0], ZERO_TX);
                assert.equal(pendingReceives[0], ZERO_TX);
                assert.equal(pendingTransfers[1], ZERO_TX);
                assert.equal(pendingReceives[1], ZERO_TX);

                const ownerBalance = await token.balanceOf(owner);
                assert.equal(ownerBalance, 10000000 * (10 ** 18) - amount);

                const receiveBalance = await token.balanceOf(to);
                assert.equal(receiveBalance, amount);
            });
    
            it('emits a transfer event', async function () {
                const { logs } = await token.transfer(to, amount, { from: owner });

                assert.equal(logs.length, 1);
                assert.equal(logs[0].event, 'Transfer');
                assert.equal(logs[0].args.from, owner);
                assert.equal(logs[0].args.to, to);
                assert(logs[0].args.value.eq(amount));
            });
        });        
    });
  
    describe('balanceOf', function () {
        describe('when the requested account has no tokens', function () {
            it('returns zero', async function () {
                const balance = await token.balanceOf(anyone);
  
                assert.equal(balance, 0);
            });
        });
        
        describe('when the requested account has some tokens', function () {
            it('returns the total amount of tokens', async function () {
                const balance = await token.balanceOf(owner);

                assert.equal(balance, 10000000 * (10 ** 18));
            });
        });
    });

    describe('Only onwer can add/remove address to/from blacklist', function () {
        it('should not allow "anyone" to add a address to the blacklist', async function () {
            await expectThrow(
                token.addAddressToBlacklist(blacklistedAddress1, { from: anyone })
            );
        });
        
        it('should not allow "anyone" to remove a address from the blacklist', async function () {
            await expectThrow(
                token.removeAddressFromBlacklist(blacklistedAddress1, { from: anyone })
            );
        });
    })    

    describe('Should add address(es) into blacklist', function () {
        it('should add address to the blacklist', async function () {
            await expectEvent.inTransaction(
                token.addAddressToBlacklist(blacklistedAddress1, { from: owner }),
                'BlacklistedAddressAdded'
            );
            const isBlacklisted = await token.blacklist(blacklistedAddress1);
            isBlacklisted.should.be.equal(true);
        });
      
        it('should add addresses to the blacklist', async function () {
            await expectEvent.inTransaction(
                token.addAddressesToBlacklist(blacklistedAddresses, { from: owner }),
                'BlacklistedAddressAdded'
            );
            for (let addr of blacklistedAddresses) {
                const isBlacklisted = await token.blacklist(addr);
                isBlacklisted.should.be.equal(true);
            }
        });        
    })
});