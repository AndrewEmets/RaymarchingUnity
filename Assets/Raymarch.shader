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

            // setup
            uniform sampler2D _MainTex;
            uniform sampler2D _CameraDepthTexture;
            uniform float4x4 _CamFrustum, _CamToWorld;
            uniform float _MaxDistance;
            
            uniform fixed4 _GroundColor;
            uniform fixed4 _SphereColors[8];
            uniform float _ColorIntencity;
            
            // sdf
            uniform float4 Sphere1Params;
            uniform float smoothSDF;
            uniform float angle;

            // Shadow
            uniform float _SoftShadowFactor;
            uniform float _ShadowIntencity;            
            
            uniform int maxIter = 300;
            uniform float accuracy = 0.01;
            
            // AmbientOcclusion
            uniform float ao_stepsize;
            uniform float ao_intencity;
            uniform int ao_iterations;
            
            // Reflection
            uniform int _ReflectionCount;
            uniform float _ReflectionIntencity;
            uniform float _EnvReflectionIntencity;
            uniform samplerCUBE _ReflectionCube;

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
            
            float3 RotateY(float3 p, float a)
            {
                float c = cos(a);
                float s = sin(a);
                return float3(c * p.x - s * p.z, p.y, s * p.x + c * p.z);
            }
            
            float4 signedDistance(float3 p)
            {
                float4 plane1 = float4(_GroundColor.rgb, sdFloor(p));
                                
                float4 sphere = float4(_SphereColors[0].rgb, sdSphere(p - Sphere1Params.xyz, Sphere1Params.w));
                
                float res = min(plane1, sphere);
                
                for (int i = 1; i < 8; i++)
                {
                    float4 s = float4(_SphereColors[i].rgb, sdSphere(RotateY(p, angle * i) - Sphere1Params.xyz, Sphere1Params.w));
                    sphere = opSU(sphere, s, smoothSDF);
                }
                                
                return opU(opU(sphere, plane1), float4(float3(0,0,0), sdBox(p - float3(0, 2, 0), float3(1,1,1))));
            }
            
            float rand(float2 co) 
            {
                float res = frac(sin(dot(co.xy ,float2(12.9898,78.233))) * 43758.5453);
                // res = step(0.5, res);
                return res; 
            }

            float noise(float2 p)
            {
                float2 p00 = floor(p);
                float2 d = float2(1,0);
                float2 luv = frac(p);
                
                float r00 = rand(p00);
                float r01 = rand(p00 + d.yx);
                float r10 = rand(p00 + d.xy);
                float r11 = rand(p00 + d.xx);
                
                luv = smoothstep(0., 1., luv);
                
                float r0001 = lerp(r00, r10, luv.x);
                float r1011 = lerp(r01, r11, luv.x);
                
                float r = lerp(r0001, r1011, luv.y);
                
                return r;
            }
            
            float3 getNormal(float3 p)
            {
                const float eps = 0.0001;
                
                float3 d = float3(eps, -eps, 0);
                
                float3 n;
                
                n.x = signedDistance(p + d.xzz).w - signedDistance(p - d.xzz).w;
                n.y = signedDistance(p + d.zxz).w - signedDistance(p - d.zxz).w;
                n.z = signedDistance(p + d.zzx).w - signedDistance(p - d.zzx).w;
                
                return normalize(n);// + (noise(p.xz * 30.)*2.-1.)* 0.05;
            }
            
            float hardShadow(float3 ro, float3 rd, float tmin, float tmax)
            {
                for (float t = tmin; t < tmax;)
                {
                    float h = signedDistance(ro + rd * t).w;
                    
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
                    float h = signedDistance(ro + rd * t).w;
                    
                    if (h < 0.01)
                    {
                        return 0.0;
                    }
                    
                    result = min(result, k*h/t);
                    t += h;
                }
                
                return result;
            }
            
            float AmbientOcclusion(float3 p, float3 n)
            {
                float ao = 0.0;
                
                for (int i = 1; i <= ao_iterations; i++)
                {
                    float dist = ao_stepsize * i;
                    ao += max(0, (dist - signedDistance(p + n * dist).w) / dist);                                        
                }    
                
                return 1 - ao * ao_intencity;
            }
            
            fixed3 Shading(float3 p, float3 n, float3 c)
            {                
                float3 color = c.rgb * _ColorIntencity;
            
                float3 light = _LightColor0 * saturate(dot(n, _WorldSpaceLightPos0));// unity_4LightAtten0;
                
                float shadow = softShadow(p, _WorldSpaceLightPos0, 0.1, 50, _SoftShadowFactor) * 0.5 + 0.5;
                shadow = pow(shadow, _ShadowIntencity);
                
                float ao = AmbientOcclusion(p, n);
                
                return color * (light * shadow * ao * 0.8+ 0.2);
            }
            
            bool raymarching(float3 ro, float3 rd, float depth, float maxDistance, int maxIterations, inout float3 p, inout fixed3 color)
            {
                bool hit;
                fixed4 result = fixed4(0,0,0,0);
                
                float t = 0.; // distance along the ray 
                
                for (int i = 0; i < maxIterations; i++)
                {
                    if (t > maxDistance || t >= depth)
                    {
                        hit = false;
                        break;
                    }         
                    
                    p = ro + rd * t;
                    
                    float4 d = signedDistance(p);
                    //float dist = length(p) - 3;
                    if (d.w <= accuracy)
                    {
                        hit = true;
                        color = d.rgb;
                        
                        break; 
                    }  
                    
                    t += d.w;                                                
                }
                
                return hit;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float depth = LinearEyeDepth(tex2D(_CameraDepthTexture, i.uv).r);
                depth *= length(i.ray);
            
                float3 rayDir = normalize(i.ray.xyz);
                float3 rayOrigin = _WorldSpaceCameraPos.xyz;
                
                fixed4 result;
                 
                float3 hitPosition;
                fixed3 dColor;
                bool hit = raymarching(rayOrigin, rayDir, depth, _MaxDistance, maxIter, hitPosition, dColor);
                                
                if (hit)
                {
                    float3 n = getNormal(hitPosition);                    
                    float3 s = Shading(hitPosition, n, dColor);
                    result = fixed4(s, 1);          
                    float3 reflectDir = normalize(reflect(rayDir, n));
                    result += fixed4(texCUBE(_ReflectionCube, reflectDir).rgb * _EnvReflectionIntencity * _ReflectionIntencity, 0);           
                    
                    // Reflection
                    
                    if (_ReflectionCount > 0)
                    {
                        rayDir = normalize(reflect(rayDir, n));
                        rayOrigin = hitPosition + rayDir * 0.01;
                        hit = raymarching(rayOrigin, rayDir, _MaxDistance / 2., _MaxDistance / 2., maxIter / 2, hitPosition, dColor);
                        
                        if (hit)
                        {
                            float3 n = getNormal(hitPosition);                    
                            float3 s = Shading(hitPosition, n, dColor);
                            
                            result += fixed4(s * _ReflectionIntencity, 0);
                            
                            if (_ReflectionCount > 1)
                            {
                                rayDir = normalize(reflect(rayDir, n));
                                rayOrigin = hitPosition + rayDir * 0.01;
                                hit = raymarching(rayOrigin, rayDir, _MaxDistance / 4., _MaxDistance / 4., maxIter / 4, hitPosition, dColor);
                                
                                if (hit)
                                {                                
                                    float3 n = getNormal(hitPosition);                    
                                    float3 s = Shading(hitPosition, n, dColor);
                                    
                                    result += fixed4(s * _ReflectionIntencity * 0.5, 0);
                                }
                            }
                        }
                    }
                }   
                else
                {
                    result = fixed4(0,0,0,0);                    
                }            
                
                fixed3 col = tex2D(_MainTex, i.uv);
                
                result.xyz = lerp(col, result.rgb, result.a);
                                
                return fixed4(result);
            }
            ENDCG
        }
    }
}
