/* This source file is derived from the UxPlay project
 * (https://github.com/FDH2/UxPlay), specifically its FairPlay/PlayFair protocol
 * implementation, and is distributed under the MIT License.
 * Copyright (c) the UxPlay contributors.
 * https://opensource.org/licenses/MIT
 */

#ifndef PLAYFAIR_H
#define PLAYFAIR_H

void playfair_decrypt(unsigned char* message3, unsigned char* cipherText, unsigned char* keyOut);

#endif
