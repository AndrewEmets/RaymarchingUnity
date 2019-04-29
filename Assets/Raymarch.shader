Shader "Custom/Raymarch"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        
    }
    SubShader
    {
        // No culling or depth
        Cull Off ZWrite Off ZTest Always
        //Blend SrcAlpha OneMinusSrcAlpha
        
        Pass
        {
            CGPROGRAM
            
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0

            #include "UnityCG.cginc"
            #include "DistanceFunctions.cginc"
            #include "Lighting.cginc"

            uniform sampler2D _MainTex;
            uniform sampler2D _CameraDepthTexture;
            uniform float4x4 _CamFrustum, _CamToWorld;
            uniform float _MaxDistance;
            uniform fixed4 _MainColor;
            
            uniform float4 Sphere1Params;
            uniform float4 Box1Params;
            uniform float3 _modInterval;

            uniform float _SoftShadowFactor;
            uniform float _ShadowIntencity;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 ray : TEXCOORD1;
            };

            v2f vert (appdata v)
            {
                v2f o;
                half index = v.vertex.z;
                v.vertex.z = 0;
                
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;                

                o.ray = _CamFrustum[(int)index].xyz;
                o.ray /= abs(o.ray.z);
                o.ray = mul(_CamToWorld, o.ray);
                
                return o;
            }
            
            float signedDistance(float3 p)
            {
                /*
                float modX = pMod1(p.x, _modInterval.x);
                float modY = pMod1(p.y, _modInterval.y);
                float modZ = pMod1(p.z, _modInterval.z);
                */
                
                float sphere1 = sdSphere(p - Sphere1Params.xyz, Sphere1Params.w);
                float box1 = sdRoundBox(p - Box1Params.xyz, Box1Params.w, 1.0);
                float plane1 = sdFloor(p);
                float res = opU(plane1, opS(sphere1, box1));
                
                return res;
            }
            
            float3 getNormal(float3 p)
            {
                const float eps = 0.0001;
                
                float3 d = float3(eps, -eps, 0);
                
                float3 n;
                
                n.x = signedDistance(p + d.xzz) - signedDistance(p - d.xzz);
                n.y = signedDistance(p + d.zxz) - signedDistance(p - d.zxz);
                n.z = signedDistance(p + d.zzx) - signedDistance(p - d.zzx);
                
                return normalize(n);
            }
            
            float hardShadow(float3 ro, float3 rd, float tmin, float tmax)
            {
                for (float t = tmin; t < tmax;)
                {
                    float h = signedDistance(ro + rd * t);
                    
                    if (h < 0.01)
                    {
                        return 0.0;
                    }
                    
                    t += h;
                }
                
                return 1.0;
            }
            
            float softShadow(float3 ro, float3 rd, float tmin, float tmax, float k)
            {
                float result = 1.0;
                
                for (float t = tmin; t < tmax;)
                {
                    float h = signedDistance(ro + rd * t);
                    
                    if (h < 0.01)
                    {
                        return 0.0;
                    }
                    
                    result = min(result, k*h/t);
                    t += h;
                }
                
                return result;
            }
            
            fixed3 Shading(float3 p, float3 n)
            {                
                float3 res = _LightColor0 * dot(n, _WorldSpaceLightPos0);// * unity_4LightAtten0;
                res = saturate(res);
                
                float shadow = softShadow(p, _WorldSpaceLightPos0, 0.1, 50, _SoftShadowFactor) * 0.5 + 0.5;
                shadow = pow(shadow, _ShadowIntencity);
                
                return res * shadow;
            }
            
            static const int maxIter = 300;
            fixed4 raymarching(float3 ro, float3 rd, float depth)
            {
                fixed4 result = fixed4(0,0,0,0);
                
                float t = 0.; // distance along the ray 
                
                for (int i = 0; i < maxIter; i++)
                {
                    if (t > _MaxDistance || t >= depth)
                    {
                        result = fixed4(0,0,0, 0);
                        break;
                    }         
                    
                    float3 p = ro + rd * t;
                    
                    float dist = signedDistance(p);
                    //float dist = length(p) - 3;
                    if (dist <= 0.002)
                    {
                        float3 n = getNormal(p);
                        
                        float3 s = Shading(p, n);
                        
                        result = fixed4(_MainColor.rgb * s, 1);
                        
                        break; 
                    }  
                    
                    t += dist;                                                
                }
                
                return result;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float depth = LinearEyeDepth(tex2D(_CameraDepthTexture, i.uv).r);
                depth *= length(i.ray);
            
                float3 rayDir = normalize(i.ray.xyz);
                float3 rayOrigin = _WorldSpaceCameraPos.xyz;
                
                fixed4 result = raymarching(rayOrigin, rayDir, depth);
                                
                fixed3 col = tex2D(_MainTex, i.uv);
                
                result.xyz = lerp(col, result.rgb, result.a);
                                
                return fixed4(result);
            }
            ENDCG
        }
    }
}
