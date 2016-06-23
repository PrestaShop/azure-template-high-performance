test template with these commands

`azure group create testhpps northeurope`  
```bash
azure group deployment create testhpps hppsdpl \
   --template-uri https://raw.githubusercontent.com/PrestaShop/azure-template-high-performance/master/mainTemplate.json \
   --parameters-file mainTemplate.parameters.json
```
