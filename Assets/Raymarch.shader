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

        Pass
        {
            CGPROGRAM
            
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0

            #include "UnityCG.cginc"

            sampler2D _MainTex;
            uniform float4x4 _CamFrustum, _CamToWorld;
            uniform float _MaxDistance;

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
            
            
            float sdSphere(float3 pos, float size)
            {
                return length(pos) - size;
            }
            
            float signedDistance(float3 p)
            {
                float result = sdSphere(p, 3);
                
                return result;
            }
            
            static const int maxIter = 100;
            fixed4 raymarching(float3 ro, float3 rd)
            {
                fixed4 result = fixed4(0,1,1,1);
                
                float t = 0.; // distance along the ray 
                
                for (int i = 0; i < 100; i++)
                {
                    if (t > _MaxDistance)
                    {
                        result = fixed4(rd, 1);
                        break;
                    }         
                    
                    float3 p = ro + rd * t;
                    
                    float dist = signedDistance(p);
                    //float dist = length(p) - 3;
                    if (dist <= 0.01)
                    {
                        result = fixed4(1,1,1,1);
                        break; 
                    }  
                    
                    t += dist;                                                
                }
                
                return result;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float3 rayDir = normalize(i.ray.xyz);
                float3 rayOrigin = _WorldSpaceCameraPos.xyz;
                
                fixed4 result = raymarching(rayOrigin, rayDir);
                
                return fixed4(result);
            }
            ENDCG
        }
    }
}
