import { SealClient, getAllowlistedKeyServers } from '@mysten/seal';
import { getFullnodeUrl, SuiClient } from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import * as dotenv from 'dotenv';

// Load environment variables
dotenv.config();

// Game actions enum matching Move contract
enum Action {
    SCISSORS = 0,
    STONE = 1,
    PAPER = 2
}

async function commitAction() {
    try {
        // Configuration from environment
        const privateKey = process.env.PRIVATE_KEY;
        const packageId = process.env.PACKAGE_ID;
        const gameId = process.env.GAME_ID;
        const network = (process.env.SEAL_NETWORK || 'testnet') as 'testnet' | 'mainnet';
        
        if (!privateKey || !packageId || !gameId) {
            throw new Error('Missing required environment variables: PRIVATE_KEY, PACKAGE_ID, or GAME_ID');
        }

        // Initialize Sui client
        const suiClient = new SuiClient({ 
            url: getFullnodeUrl(network) 
        });

        // Create keypair from private key
        const keypair = Ed25519Keypair.fromSecretKey(privateKey);
        const address = keypair.toSuiAddress();
        
        console.log('Player address:', address);
        console.log('Using network:', network);

        // Get allowlisted key servers for testnet
        const keyServerIds = getAllowlistedKeyServers(network);
        console.log('Key servers:', keyServerIds);

        // Initialize Seal client
        const sealClient = new SealClient({
            suiClient,
            serverConfigs: keyServerIds.map(id => ({
                objectId: id,
                weight: 1
            })),
            verifyKeyServers: true
        });

        // Get user input for action
        const actionChoice = await getUserAction();
        const actionByte = new Uint8Array([actionChoice]);
        
        console.log(`\nEncrypting action: ${Action[actionChoice]}`);

        // Create encryption parameters
        // The package ID and game ID are used to create a unique encryption context
        // This ensures that the encrypted object can only be decrypted in the context of this specific game
        const encryptionParams = {
            threshold: Math.ceil(keyServerIds.length * 2 / 3), // 2/3 threshold
            packageId: packageId,
            id: gameId, // The game ID acts as the encryption context
            data: actionByte
        };

        // Encrypt the action
        console.log('Encrypting with Seal...');
        const { encryptedObject } = await sealClient.encrypt(encryptionParams);
        
        console.log('\nEncrypted object created:');
        console.log('- Package ID:', encryptedObject.packageId);
        console.log('- Object ID:', encryptedObject.id);
        console.log('- Threshold:', encryptedObject.threshold);
        console.log('- Key servers:', encryptedObject.keyServers.length);
        console.log('- Encrypted blob size:', encryptedObject.encryptedBlob.length);

        // Create transaction to submit the encrypted action to the game
        const tx = new Transaction();
        
        // Call the playRound function with the encrypted object
        tx.moveCall({
            target: `${packageId}::rps::playRound`,
            arguments: [
                tx.object(gameId), // Game object
                tx.pure.address(encryptedObject), // EncryptedObject
                tx.object('0x6'), // Clock object
            ],
        });

        // Execute transaction
        console.log('\nSubmitting encrypted action to blockchain...');
        const result = await suiClient.signAndExecuteTransaction({
            signer: keypair,
            transaction: tx,
        });

        console.log('\n Action committed successfully!');
        console.log('Transaction digest:', result.digest);
        console.log('View on explorer:', `https://testnet.suivision.xyz/tx/${result.digest}`);

        // Save the encrypted object for later reveal
        saveEncryptedObject(gameId, encryptedObject);

    } catch (error) {
        console.error('L Error committing action:', error);
        process.exit(1);
    }
}

async function getUserAction(): Promise<Action> {
    console.log('\nChoose your action:');
    console.log('0 - SCISSORS ');
    console.log('1 - STONE =ÿ');
    console.log('2 - PAPER =Ä');
    
    return new Promise((resolve) => {
        process.stdin.once('data', (data) => {
            const choice = parseInt(data.toString().trim());
            if (choice >= 0 && choice <= 2) {
                resolve(choice as Action);
            } else {
                console.log('Invalid choice. Using SCISSORS as default.');
                resolve(Action.SCISSORS);
            }
        });
    });
}

function saveEncryptedObject(gameId: string, encryptedObject: any) {
    // In production, save this to a database or file
    // For now, just log it
    console.log('\n=Á Save this encrypted object for revealing later:');
    console.log(JSON.stringify({
        gameId,
        encryptedObject,
        timestamp: new Date().toISOString()
    }, null, 2));
}

// Run the script
commitAction();