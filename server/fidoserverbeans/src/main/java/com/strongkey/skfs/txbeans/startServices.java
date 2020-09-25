/**
 * Copyright StrongAuth, Inc. All Rights Reserved.
 *
 * Use of this source code is governed by the GNU Lesser General Public License v2.1
 * The license can be found at https://github.com/StrongKey/fido2/blob/master/LICENSE
 */
package com.strongkey.skfs.txbeans;

import com.strongkey.appliance.entitybeans.Domains;
import com.strongkey.appliance.utilities.applianceCommon;
import com.strongkey.appliance.utilities.applianceMaps;
import com.strongkey.crypto.utility.CryptoException;
import com.strongkey.crypto.utility.cryptoCommon;
import com.strongkey.skce.utilities.skceCommon;
import com.strongkey.skfs.messaging.SKCEBacklogProcessor;
import com.strongkey.skfs.utilities.skfsCommon;
import java.util.Collection;
import javax.annotation.PostConstruct;
import javax.ejb.EJB;
import javax.ejb.Singleton;
import javax.ejb.Startup;

@Singleton
@Startup
public class startServices {

    @EJB
    getDomainsBeanLocal getdomejb;

    final private String SIGN_SUFFIX = skfsCommon.getConfigurationProperty("skfs.cfg.property.signsuffix");

    @PostConstruct
    public void initialize() {

        String standalone = skfsCommon.getConfigurationProperty("skfs.cfg.property.standalone.fidoengine");
        if (standalone.equalsIgnoreCase("true")) {
            skceCommon.getConfigurationProperty("skce.cfg.property.skcehome");
            Collection<Domains> domains = getdomejb.getAll();

            if (domains != null) {
                for (Domains d : domains) {
                    Long did = d.getDid();

                    // Cache domain objects
                    applianceMaps.putDomain(did, d);

                    try {
                        cryptoCommon.loadSigningKey(did.toString(), skfsCommon.getConfigurationProperty("skfs.cfg.property.standalone.signingkeystore.password"), d.getSkceSigningdn());
                        cryptoCommon.loadVerificationKey(did.toString(), skfsCommon.getConfigurationProperty("skfs.cfg.property.standalone.signingkeystore.password"), d.getSkceSigningdn());
                    } catch (CryptoException ex) {
                        ex.printStackTrace();
                    }
                }
            }

            //set replication to false
            if (applianceCommon.getApplianceConfigurationProperty("appliance.cfg.property.replicate").equalsIgnoreCase("true")) {
                applianceCommon.setReplicateStatus(Boolean.TRUE);
                SKCEBacklogProcessor.getInstance();

            } else {
                applianceCommon.setReplicateStatus(Boolean.FALSE);
            }
        }
    }
}
