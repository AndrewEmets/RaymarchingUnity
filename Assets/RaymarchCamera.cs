using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[RequireComponent(typeof(Camera))]
[ExecuteInEditMode]
public class RaymarchCamera : SceneViewFilter
{
    [SerializeField] private Shader shader;
    [SerializeField] private float maxDistance;
    [SerializeField] private Color color;
    [SerializeField] private Vector4 sphere1, box1;
    [SerializeField] private Vector3 modInterval;
    [SerializeField, Range(0.001f, 0.2f)] private float accuracy = 0.01f;
    [SerializeField, Range(32, 512)] private int maxIterations = 128;

    [Header("Shadow")] [SerializeField, Range(0, 10)]
    private float shadowIntencity;
    [SerializeField, Range(1,300)] private float softShadowFactor;

    [Header("Ambient occlusion"), SerializeField]
    private float ao_stepSize;

    [SerializeField] private float ao_intencity;
    [SerializeField] private int ao_steps;
    
    public Material Material
    {
        get
        {
            if (material == null)
            {
                if (shader != null)
                    material = new Material(shader) {hideFlags = HideFlags.HideAndDontSave};
            }

            return material;
        }
    }

    private Material material;

    private Camera camera;
    private static readonly int shadowIntencityID = Shader.PropertyToID("_ShadowIntencity");

    public Camera Camera
    {
        get
        {
            if (camera == null)
            {
                camera = GetComponent<Camera>();
            }

            return camera;
        }
    }

    private void OnRenderImage(RenderTexture src, RenderTexture dest)
    {
        if (Material == null)
        {
            Graphics.Blit(src, dest);
        }

        material.SetMatrix("_CamFrustum", CamFrustum(Camera));
        material.SetMatrix("_CamToWorld", Camera.cameraToWorldMatrix);
        material.SetFloat("_MaxDistance", maxDistance);
        material.SetColor("_MainColor", color);
        material.SetVector("Sphere1Params", sphere1);
        material.SetVector("Box1Params", box1);
        material.SetVector("_modInterval", modInterval);
        material.SetFloat("_SoftShadowFactor", Mathf.Sqrt(softShadowFactor));
        material.SetFloat(shadowIntencityID, shadowIntencity);
        material.SetFloat("accuracy", accuracy);
        material.SetInt("maxIter", maxIterations);
        
        material.SetFloat("ao_stepsize", ao_stepSize);
        material.SetFloat("ao_intencity", ao_intencity);
        material.SetInt("ao_iterations", ao_steps);
        
        RenderTexture.active = dest;
        material.mainTexture = src;
        
        GL.PushMatrix();
        GL.LoadOrtho();
        material.SetPass(0);

        GL.Begin(GL.QUADS);
        
        // BL
        GL.MultiTexCoord2(0, 0f, 0f);
        GL.Vertex3(0f, 0f, 3f);

        // TL
        GL.MultiTexCoord2(0, 0f, 1f);
        GL.Vertex3(0f, 1f, 0f);

        // TR
        GL.MultiTexCoord2(0, 1f, 1f);
        GL.Vertex3(1f, 1f, 1f);
        
        // BR
        GL.MultiTexCoord2(0, 1f, 0f);
        GL.Vertex3(1f, 0f, 2f);
        
        
        GL.End();
        
        GL.PopMatrix();
    }

    Matrix4x4 CamFrustum(Camera cam)
    {
        var frust = Matrix4x4.identity;
        var fov = Mathf.Tan((cam.fieldOfView * 0.5f) * Mathf.Deg2Rad);

        var up = Vector3.up * fov;
        var right = Vector3.right * fov * Camera.aspect;

        var TL = -Vector3.forward - right + up;
        var TR = -Vector3.forward + right + up;
        var BR = -Vector3.forward + right - up;
        var BL = -Vector3.forward - right - up;
        
        frust.SetRow(0, TL);
        frust.SetRow(1, TR);
        frust.SetRow(2, BR);
        frust.SetRow(3, BL);
        
        return frust;
    }
}
